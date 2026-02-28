import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Octomil
import OctomilMLX

/// Runs cold/warm/cache benchmark iterations against the Octomil MLX engine.
@available(macOS 14.0, *)
public struct MLXBenchmarkRunner: Sendable {

    public init() {}

    public func run(
        model: ModelSpec,
        prompt: String,
        iterations: Int,
        warmup: Int,
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        converge: Bool = false
    ) async throws -> ModelBenchmarkResult {
        let loader = MLXModelLoader(gpuCacheLimit: 2 * 1024 * 1024 * 1024)

        print("  [octomil] Loading \(model.mlxId)...")
        let container = try await loader.loadFromHub(modelId: model.mlxId)

        var allIterations: [IterationResult] = []
        var ttftCold: Double?
        var kvCacheTtft1: Double?
        var kvCacheTtft2: Double?

        // Create one engine with cacheEnabled=true — reused across all iterations
        // so KV cache persists between calls (same as Ollama's server-side cache)
        let engine = MLXLLMEngine(
            modelContainer: container,
            maxTokens: maxTokens,
            temperature: Float(temperature),
            cacheEnabled: true
        )

        // --- Cold run (first ever generation) ---
        print("  [octomil] Cold run...")
        let coldResult = try await runIteration(
            engine: engine,
            container: container,
            model: model,
            prompt: prompt,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            iteration: 0
        )
        ttftCold = coldResult.ttftMs

        // --- Warmup iterations (discarded) ---
        for w in 0..<warmup {
            print("  [octomil] Warmup \(w + 1)/\(warmup)...")
            _ = try await runIteration(
                engine: engine,
                container: container,
                model: model,
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                iteration: -1
            )
        }

        // --- Measured iterations (with optional auto-convergence) ---
        let minIterations = converge ? Swift.max(5, iterations / 2) : iterations
        for i in 0..<iterations {
            print("  [octomil] Iteration \(i + 1)/\(iterations)...")
            let result = try await runIteration(
                engine: engine,
                container: container,
                model: model,
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                iteration: i + 1
            )
            allIterations.append(result)

            // Auto-convergence: stop when CV < 5% after minimum iterations
            if converge && allIterations.count >= minIterations {
                let toks = allIterations.map(\.tokensPerSecond)
                let mean = toks.reduce(0, +) / Double(toks.count)
                let variance = toks.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(toks.count - 1)
                let cv = mean > 0 ? variance.squareRoot() / mean : 1.0
                if cv < 0.05 {
                    print("  [octomil] Converged at iteration \(i + 1) (CV=\(String(format: "%.1f", cv * 100))%)")
                    break
                }
            }
        }

        // --- KV cache measurement ---
        // Measure cache reuse via direct generate calls with explicit cache management.
        // This isolates the KV cache speedup from other engine overhead.
        print("  [octomil] KV cache test (run 1, populate cache)...")
        let cacheTestResult1 = try await runIterationDirect(
            container: container,
            prompt: prompt,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            existingCache: nil
        )
        kvCacheTtft1 = cacheTestResult1.ttftMs

        print("  [octomil] KV cache test (run 2, reuse cache)...")
        let cacheTestResult2 = try await runIterationDirect(
            container: container,
            prompt: prompt,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            existingCache: cacheTestResult1.cache,
            previousTokenIds: cacheTestResult1.promptTokenIds
        )
        kvCacheTtft2 = cacheTestResult2.ttftMs

        // Compute averages
        let stats = BenchmarkStats.compute(from: allIterations)
        let memMb = Double(Memory.activeMemory) / (1024 * 1024)

        let kvSpeedup: Double? = {
            guard let t1 = kvCacheTtft1, let t2 = kvCacheTtft2, t2 > 0 else { return nil }
            return t1 / t2
        }()

        // Evict to free GPU memory
        await loader.evictAll()

        let outputPreview: String? = allIterations.first.map {
            let text = $0.outputText.prefix(120)
            return text.count < $0.outputText.count
                ? String(text) + "..."
                : String(text)
        }

        let benchResult = BenchmarkResult(
            engineName: "octomil",
            tokensPerSecond: stats.tokPerSec.mean,
            ttftMs: stats.ttftMs.mean,
            memoryMb: memMb,
            metadata: ["model": model.mlxId, "params": model.params]
        )

        let params = GenerationParams(
            prompt: prompt,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            prefillStepSize: 4096,
            cacheEnabled: true,
            gpuCacheLimitMb: 2048,
            quantization: "4bit"
        )

        return ModelBenchmarkResult(
            engine: "octomil",
            model: model,
            result: benchResult,
            params: params,
            ttftColdMs: ttftCold,
            ttftWarmMs: stats.ttftMs.mean,
            tpotMs: stats.tpotMs.mean,
            e2eMs: stats.e2eMs.mean,
            kvCacheSpeedup: kvSpeedup,
            iterationResults: allIterations,
            stats: stats,
            outputPreview: outputPreview,
            memBandwidthGBs: stats.memBandwidthGBs.mean,
            power: nil,     // Set by orchestrator
            energyPerTokenMJ: nil
        )
    }

    // MARK: - Via MLXLLMEngine + InstrumentedStreamWrapper (standard path)

    private func runIteration(
        engine: MLXLLMEngine,
        container: ModelContainer,
        model: ModelSpec,
        prompt: String,
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        iteration: Int
    ) async throws -> IterationResult {
        let wrapper = InstrumentedStreamWrapper(modality: .text, modelId: "bench")
        let (stream, getResult) = wrapper.wrap(engine, input: prompt)

        var outputText = ""
        var chunkCount = 0

        for try await chunk in stream {
            if let text = String(data: chunk.data, encoding: .utf8) {
                outputText += text
            }
            chunkCount += 1
        }

        guard let metrics = getResult() else {
            throw BenchRunError.noMetrics
        }

        // Get actual token count from the tokenizer
        let promptTokens = try await container.perform { context in
            context.tokenizer.encode(text: prompt).count
        }

        let tpot: Double = chunkCount > 1
            ? (metrics.totalDurationMs - metrics.ttfcMs) / Double(chunkCount - 1)
            : metrics.totalDurationMs

        // Effective decode bandwidth: each token reads all model weights
        let bw = model.weightSizeBytes * metrics.throughput / 1e9

        return IterationResult(
            iteration: iteration,
            tokensPerSecond: metrics.throughput,
            tpotMs: tpot,
            ttftMs: metrics.ttfcMs,
            e2eMs: metrics.totalDurationMs,
            promptTokens: promptTokens,
            outputTokens: chunkCount,
            outputText: outputText,
            totalDurationMs: metrics.totalDurationMs,
            memBandwidthGBs: bw
        )
    }

    // MARK: - Direct MLXLMCommon.generate (for KV cache test)

    /// Result from a direct generation call, including the KV cache for reuse.
    private struct DirectResult: @unchecked Sendable {
        let ttftMs: Double
        let cache: [KVCache]?
        let promptTokenIds: [Int]
    }

    /// Runs generation directly via MLXLMCommon.generate to properly manage KV cache.
    /// When existingCache is provided, trims it to the common prefix and reuses it.
    private func runIterationDirect(
        container: ModelContainer,
        prompt: String,
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        existingCache: [KVCache]?,
        previousTokenIds: [Int]? = nil
    ) async throws -> DirectResult {
        let start = CFAbsoluteTimeGetCurrent()
        var firstTokenTime: Double?

        let (genStream, cache, promptTokenIds) = try await container.perform {
            context -> (AsyncStream<Generation>, [KVCache], [Int]) in

            let prepared = try await context.processor.prepare(
                input: .init(prompt: prompt))
            let promptTokenIds = context.tokenizer.encode(text: prompt)

            // Create or reuse cache
            let cache: [KVCache]
            if let existing = existingCache, let prevTokens = previousTokenIds {
                // Trim cache to common prefix between previous and current prompt
                let commonLen = zip(promptTokenIds, prevTokens).prefix(while: { $0 == $1 }).count
                for kv in existing {
                    if kv.isTrimmable && kv.offset > commonLen - 1 {
                        let excess = kv.offset - (commonLen - 1)
                        if excess > 0 { kv.trim(excess) }
                    }
                }
                cache = existing
            } else {
                cache = context.model.newCache(parameters: nil)
            }

            let stream = try MLXLMCommon.generate(
                input: prepared,
                cache: cache,
                parameters: .init(
                    maxTokens: maxTokens,
                    temperature: Float(temperature),
                    topP: Float(topP),
                    prefillStepSize: 4096
                ),
                context: context
            )

            return (stream, cache, promptTokenIds)
        }

        for await generation in genStream {
            switch generation {
            case .chunk:
                if firstTokenTime == nil {
                    firstTokenTime = CFAbsoluteTimeGetCurrent()
                }
            case .info, .toolCall:
                break
            }
        }

        let ttftMs = ((firstTokenTime ?? start) - start) * 1000
        return DirectResult(ttftMs: ttftMs, cache: cache, promptTokenIds: promptTokenIds)
    }
}

enum BenchRunError: Error, LocalizedError {
    case noMetrics
    case ollamaNotAvailable

    var errorDescription: String? {
        switch self {
        case .noMetrics: return "Failed to collect benchmark metrics"
        case .ollamaNotAvailable: return "Ollama is not running at localhost:11434"
        }
    }
}
