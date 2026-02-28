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
    public let skipLlamaCpp: Bool
    public let pullMissing: Bool
    public let converge: Bool

    public init(
        models: [ModelSpec],
        iterations: Int = 10,
        warmup: Int = 3,
        maxTokens: Int = 128,
        temperature: Double = 0.0,
        topP: Double = 0.9,
        prompt: String = "Explain the theory of general relativity in simple terms.",
        skipOllama: Bool = false,
        skipMlx: Bool = false,
        skipLlamaCpp: Bool = false,
        pullMissing: Bool = false,
        converge: Bool = false
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
        self.skipLlamaCpp = skipLlamaCpp
        self.pullMissing = pullMissing
        self.converge = converge
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

        // Start power sampling (requires root — silently skipped if unavailable)
        let sampler = PowerSampler()
        sampler.start()

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
                        topP: topP,
                        converge: converge
                    )
                    results.append(result)
                    print("  [octomil] Done: \(String(format: "%.1f", result.result.tokensPerSecond)) tok/s | \(String(format: "%.1f", result.memBandwidthGBs ?? 0)) GB/s")
                } catch {
                    print("  [octomil] FAILED: \(error.localizedDescription)")
                    results.append(errorResult(engine: "octomil", model: model, error: error))
                }
            }

            // MLX Raw (no engine overhead — proves MLX's actual speed)
            if !skipMlx {
                do {
                    let mlxRunner = MLXBenchmarkRunner()
                    let result = try await mlxRunner.runRaw(
                        model: model,
                        prompt: prompt,
                        iterations: iterations,
                        warmup: warmup,
                        maxTokens: maxTokens,
                        temperature: temperature,
                        topP: topP,
                        converge: converge
                    )
                    results.append(result)
                    print("  [mlx-raw] Done: \(String(format: "%.1f", result.result.tokensPerSecond)) tok/s | \(String(format: "%.1f", result.memBandwidthGBs ?? 0)) GB/s")
                } catch {
                    print("  [mlx-raw] FAILED: \(error.localizedDescription)")
                    results.append(errorResult(engine: "mlx-raw", model: model, error: error))
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
                        pullMissing: pullMissing,
                        converge: converge
                    )
                    results.append(result)
                    print("  [ollama] Done: \(String(format: "%.1f", result.result.tokensPerSecond)) tok/s | \(String(format: "%.1f", result.memBandwidthGBs ?? 0)) GB/s")
                } catch {
                    print("  [ollama] FAILED: \(error.localizedDescription)")
                    results.append(errorResult(engine: "ollama", model: model, error: error))
                }
            }

            // llama.cpp (raw, no Ollama HTTP layer)
            if !skipLlamaCpp {
                do {
                    let llamaRunner = LlamaCppBenchmarkRunner()
                    guard llamaRunner.isAvailable() else {
                        print("  [llama.cpp] SKIPPED: llama-cli not found")
                        continue
                    }
                    let result = try await llamaRunner.run(
                        model: model,
                        prompt: prompt,
                        iterations: iterations,
                        warmup: warmup,
                        maxTokens: maxTokens,
                        temperature: temperature,
                        topP: topP,
                        converge: converge
                    )
                    results.append(result)
                    print("  [llama.cpp] Done: \(String(format: "%.1f", result.result.tokensPerSecond)) tok/s | \(String(format: "%.1f", result.memBandwidthGBs ?? 0)) GB/s")
                } catch {
                    print("  [llama.cpp] FAILED: \(error.localizedDescription)")
                    results.append(errorResult(engine: "llama.cpp", model: model, error: error))
                }
            }
        }

        // Stop power sampling and attach readings
        let powerReading = sampler.stop()
        if let power = powerReading {
            print("\nPower: GPU \(String(format: "%.1f", power.gpuW))W + CPU \(String(format: "%.1f", power.cpuW))W = \(String(format: "%.1f", power.totalW))W (\(power.sampleCount) samples)")
            // Attach power readings and compute energy per token
            results = results.map { r in
                let energyPerToken = r.result.tokensPerSecond > 0
                    ? power.totalW * 1000.0 / r.result.tokensPerSecond
                    : nil
                return ModelBenchmarkResult(
                    engine: r.engine,
                    model: r.model,
                    result: r.result,
                    params: r.params,
                    ttftColdMs: r.ttftColdMs,
                    ttftWarmMs: r.ttftWarmMs,
                    tpotMs: r.tpotMs,
                    e2eMs: r.e2eMs,
                    kvCacheSpeedup: r.kvCacheSpeedup,
                    iterationResults: r.iterationResults,
                    stats: r.stats,
                    outputPreview: r.outputPreview,
                    memBandwidthGBs: r.memBandwidthGBs,
                    power: power,
                    energyPerTokenMJ: energyPerToken
                )
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
            prefillStepSize: engine == "octomil" ? 4096 : nil,
            cacheEnabled: engine == "octomil" ? true : nil,
            gpuCacheLimitMb: engine == "octomil" ? 2048 : nil,
            quantization: engine == "octomil" ? "4bit" : "q4_0"
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
            iterationResults: [],
            stats: nil,
            outputPreview: nil,
            memBandwidthGBs: nil,
            power: nil,
            energyPerTokenMJ: nil
        )
    }
}
