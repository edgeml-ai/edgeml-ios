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
        topP: Double
    ) async throws -> ModelBenchmarkResult {
        let loader = MLXModelLoader(gpuCacheLimit: 2 * 1024 * 1024 * 1024)

        print("  [octomil] Loading \(model.mlxId)...")
        let container = try await loader.loadFromHub(modelId: model.mlxId)

        var allIterations: [IterationResult] = []
        var ttftCold: Double?
        var kvCacheTtft1: Double?
        var kvCacheTtft2: Double?

        // --- Cold run (first ever generation) ---
        print("  [octomil] Cold run...")
        let coldResult = try await runIteration(
            container: container,
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
                container: container,
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                iteration: -1
            )
        }

        // --- Measured iterations ---
        for i in 0..<iterations {
            print("  [octomil] Iteration \(i + 1)/\(iterations)...")
            let result = try await runIteration(
                container: container,
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                iteration: i + 1
            )
            allIterations.append(result)
        }

        // --- KV cache measurement ---
        // Create a persistent cache outside the engine so it survives across calls.
        // MLXLLMEngine's internal cache storage has a bug where the first generation's
        // KV cache is never captured (nil stored), so we measure via direct generate calls.
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
            existingCache: cacheTestResult1.cache
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
            outputPreview: outputPreview
        )
    }

    // MARK: - Via MLXLLMEngine + InstrumentedStreamWrapper (standard path)

    private func runIteration(
        container: ModelContainer,
        prompt: String,
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        iteration: Int
    ) async throws -> IterationResult {
        let engine = MLXLLMEngine(
            modelContainer: container,
            maxTokens: maxTokens,
            temperature: Float(temperature),
            cacheEnabled: false
        )
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

        return IterationResult(
            iteration: iteration,
            tokensPerSecond: metrics.throughput,
            tpotMs: tpot,
            ttftMs: metrics.ttfcMs,
            e2eMs: metrics.totalDurationMs,
            promptTokens: promptTokens,
            outputTokens: chunkCount,
            outputText: outputText,
            totalDurationMs: metrics.totalDurationMs
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
        existingCache: [KVCache]?
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
            if let existing = existingCache {
                // Trim cache to match prompt prefix
                let commonLen = zip(promptTokenIds, promptTokenIds).prefix(while: { $0 == $1 }).count
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
