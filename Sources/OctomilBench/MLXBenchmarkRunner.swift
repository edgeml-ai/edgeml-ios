import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import Octomil
import OctomilMLX

/// Runs cold/warm/cache benchmark iterations against the MLX engine.
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

        print("  [mlx] Loading \(model.mlxId)...")
        let container = try await loader.loadFromHub(modelId: model.mlxId)

        var allIterations: [IterationResult] = []
        var ttftCold: Double?
        var kvCacheTtft1: Double?
        var kvCacheTtft2: Double?

        // --- Cold run (first ever generation) ---
        print("  [mlx] Cold run...")
        let coldResult = try await runSingleIteration(
            container: container,
            prompt: prompt,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            cacheEnabled: false,
            iteration: 0
        )
        ttftCold = coldResult.ttftMs

        // --- Warmup iterations (discarded) ---
        for w in 0..<warmup {
            print("  [mlx] Warmup \(w + 1)/\(warmup)...")
            _ = try await runSingleIteration(
                container: container,
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                cacheEnabled: false,
                iteration: -1
            )
        }

        // --- Measured iterations ---
        for i in 0..<iterations {
            print("  [mlx] Iteration \(i + 1)/\(iterations)...")
            let result = try await runSingleIteration(
                container: container,
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP,
                cacheEnabled: false,
                iteration: i + 1
            )
            allIterations.append(result)
        }

        // --- KV cache measurement: same prompt twice with cache enabled ---
        print("  [mlx] KV cache test (run 1)...")
        let cacheEngine1 = MLXLLMEngine(
            modelContainer: container,
            maxTokens: maxTokens,
            temperature: Float(temperature),
            cacheEnabled: true
        )
        let cacheResult1 = try await runWithEngine(
            engine: cacheEngine1,
            prompt: prompt,
            maxTokens: maxTokens,
            iteration: -1
        )
        kvCacheTtft1 = cacheResult1.ttftMs

        print("  [mlx] KV cache test (run 2, cache reuse)...")
        let cacheResult2 = try await runWithEngine(
            engine: cacheEngine1,
            prompt: prompt,
            maxTokens: maxTokens,
            iteration: -1
        )
        kvCacheTtft2 = cacheResult2.ttftMs

        // Compute averages
        let avgTokS = allIterations.map(\.tokensPerSecond).reduce(0, +) / Double(allIterations.count)
        let avgTpot = allIterations.map(\.tpotMs).reduce(0, +) / Double(allIterations.count)
        let avgTtft = allIterations.map(\.ttftMs).reduce(0, +) / Double(allIterations.count)
        let avgE2e = allIterations.map(\.e2eMs).reduce(0, +) / Double(allIterations.count)
        let memMb = Double(Memory.activeMemory) / (1024 * 1024)

        let kvSpeedup: Double? = {
            guard let t1 = kvCacheTtft1, let t2 = kvCacheTtft2, t2 > 0 else { return nil }
            return t1 / t2
        }()

        // Evict to free GPU memory
        await loader.evictAll()

        let benchResult = BenchmarkResult(
            engineName: "mlx",
            tokensPerSecond: avgTokS,
            ttftMs: avgTtft,
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
            engine: "mlx",
            model: model,
            result: benchResult,
            params: params,
            ttftColdMs: ttftCold,
            ttftWarmMs: avgTtft,
            tpotMs: avgTpot,
            e2eMs: avgE2e,
            kvCacheSpeedup: kvSpeedup,
            iterationResults: allIterations
        )
    }

    // MARK: - Single Iteration

    private func runSingleIteration(
        container: ModelContainer,
        prompt: String,
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        cacheEnabled: Bool,
        iteration: Int
    ) async throws -> IterationResult {
        let engine = MLXLLMEngine(
            modelContainer: container,
            maxTokens: maxTokens,
            temperature: Float(temperature),
            cacheEnabled: cacheEnabled
        )
        return try await runWithEngine(engine: engine, prompt: prompt, maxTokens: maxTokens, iteration: iteration)
    }

    private func runWithEngine(
        engine: MLXLLMEngine,
        prompt: String,
        maxTokens: Int,
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

        let promptTokens = prompt.split(separator: " ").count  // approximation
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
