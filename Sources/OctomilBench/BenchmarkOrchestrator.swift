import Foundation
import Octomil

/// Coordinates benchmark runs sequentially per model across both engines.
@available(macOS 14.0, *)
public struct BenchmarkOrchestrator: Sendable {
    public let models: [ModelSpec]
    public let iterations: Int
    public let warmup: Int
    public let maxTokens: Int
    public let temperature: Double
    public let topP: Double
    public let prompt: String
    public let skipOllama: Bool
    public let skipMlx: Bool
    public let pullMissing: Bool

    public init(
        models: [ModelSpec],
        iterations: Int = 3,
        warmup: Int = 1,
        maxTokens: Int = 128,
        temperature: Double = 0.0,
        topP: Double = 0.9,
        prompt: String = "Explain the theory of general relativity in simple terms.",
        skipOllama: Bool = false,
        skipMlx: Bool = false,
        pullMissing: Bool = false
    ) {
        self.models = models
        self.iterations = iterations
        self.warmup = warmup
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.prompt = prompt
        self.skipOllama = skipOllama
        self.skipMlx = skipMlx
        self.pullMissing = pullMissing
    }

    public func run() async throws -> [ModelBenchmarkResult] {
        var results: [ModelBenchmarkResult] = []

        // Verify Ollama availability upfront
        if !skipOllama {
            let client = OllamaClient()
            let available = await client.isAvailable()
            if !available {
                throw BenchRunError.ollamaNotAvailable
            }
        }

        for (idx, model) in models.enumerated() {
            print("\n[\(idx + 1)/\(models.count)] Benchmarking: \(model.name) (\(model.params))")
            print(String(repeating: "-", count: 50))

            // MLX
            if !skipMlx {
                do {
                    let mlxRunner = MLXBenchmarkRunner()
                    let result = try await mlxRunner.run(
                        model: model,
                        prompt: prompt,
                        iterations: iterations,
                        warmup: warmup,
                        maxTokens: maxTokens,
                        temperature: temperature,
                        topP: topP
                    )
                    results.append(result)
                    print("  [mlx] Done: \(String(format: "%.1f", result.result.tokensPerSecond)) tok/s")
                } catch {
                    print("  [mlx] FAILED: \(error.localizedDescription)")
                    results.append(errorResult(engine: "mlx", model: model, error: error))
                }
            }

            // Ollama
            if !skipOllama {
                do {
                    let ollamaRunner = OllamaBenchmarkRunner()
                    let result = try await ollamaRunner.run(
                        model: model,
                        prompt: prompt,
                        iterations: iterations,
                        warmup: warmup,
                        maxTokens: maxTokens,
                        temperature: temperature,
                        topP: topP,
                        pullMissing: pullMissing
                    )
                    results.append(result)
                    print("  [ollama] Done: \(String(format: "%.1f", result.result.tokensPerSecond)) tok/s")
                } catch {
                    print("  [ollama] FAILED: \(error.localizedDescription)")
                    results.append(errorResult(engine: "ollama", model: model, error: error))
                }
            }
        }

        return results
    }

    private func errorResult(engine: String, model: ModelSpec, error: Error) -> ModelBenchmarkResult {
        let params = GenerationParams(
            prompt: prompt,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            prefillStepSize: engine == "mlx" ? 4096 : nil,
            cacheEnabled: engine == "mlx" ? true : nil,
            gpuCacheLimitMb: engine == "mlx" ? 2048 : nil,
            quantization: engine == "mlx" ? "4bit" : "q4_0"
        )

        return ModelBenchmarkResult(
            engine: engine,
            model: model,
            result: BenchmarkResult(
                engineName: engine,
                tokensPerSecond: 0,
                ttftMs: 0,
                memoryMb: 0,
                error: error.localizedDescription
            ),
            params: params,
            ttftColdMs: nil,
            ttftWarmMs: nil,
            tpotMs: nil,
            e2eMs: nil,
            kvCacheSpeedup: nil,
            iterationResults: []
        )
    }
}
