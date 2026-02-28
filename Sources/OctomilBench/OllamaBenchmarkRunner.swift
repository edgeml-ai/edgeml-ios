import Foundation
import Octomil

/// Runs cold/warm/cache benchmark iterations against Ollama.
public struct OllamaBenchmarkRunner: Sendable {
    private let client: OllamaClient

    public init(client: OllamaClient = OllamaClient()) {
        self.client = client
    }

    public func run(
        model: ModelSpec,
        prompt: String,
        iterations: Int,
        warmup: Int,
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        pullMissing: Bool
    ) async throws -> ModelBenchmarkResult {
        // Ensure model is available
        let hasModel = try await client.hasModel(model.ollamaId)
        if !hasModel {
            if pullMissing {
                print("  [ollama] Pulling \(model.ollamaId)...")
                try await client.pullModel(model.ollamaId)
            } else {
                throw OllamaClient.OllamaError.modelNotFound(model.ollamaId)
            }
        }

        var allIterations: [IterationResult] = []
        var ttftCold: Double?
        var kvCacheTtft1: Double?
        var kvCacheTtft2: Double?

        // --- Cold run ---
        print("  [ollama] Cold run...")
        let coldResponse = try await client.generate(
            model: model.ollamaId,
            prompt: prompt,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP
        )
        ttftCold = nanosToMs(coldResponse.promptEvalDuration)

        // --- Warmup ---
        for w in 0..<warmup {
            print("  [ollama] Warmup \(w + 1)/\(warmup)...")
            _ = try await client.generate(
                model: model.ollamaId,
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP
            )
        }

        // --- Measured iterations ---
        for i in 0..<iterations {
            print("  [ollama] Iteration \(i + 1)/\(iterations)...")
            let response = try await client.generate(
                model: model.ollamaId,
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP
            )
            let result = parseIteration(response: response, iteration: i + 1, prompt: prompt)
            allIterations.append(result)
        }

        // --- KV cache measurement ---
        print("  [ollama] KV cache test (run 1)...")
        let cache1 = try await client.generate(
            model: model.ollamaId,
            prompt: prompt,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP
        )
        kvCacheTtft1 = nanosToMs(cache1.promptEvalDuration)

        print("  [ollama] KV cache test (run 2)...")
        let cache2 = try await client.generate(
            model: model.ollamaId,
            prompt: prompt,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP
        )
        kvCacheTtft2 = nanosToMs(cache2.promptEvalDuration)

        // Compute averages
        let avgTokS = allIterations.map(\.tokensPerSecond).reduce(0, +) / Double(allIterations.count)
        let avgTpot = allIterations.map(\.tpotMs).reduce(0, +) / Double(allIterations.count)
        let avgTtft = allIterations.map(\.ttftMs).reduce(0, +) / Double(allIterations.count)
        let avgE2e = allIterations.map(\.e2eMs).reduce(0, +) / Double(allIterations.count)

        let kvSpeedup: Double? = {
            guard let t1 = kvCacheTtft1, let t2 = kvCacheTtft2, t2 > 0 else { return nil }
            return t1 / t2
        }()

        let benchResult = BenchmarkResult(
            engineName: "ollama",
            tokensPerSecond: avgTokS,
            ttftMs: avgTtft,
            memoryMb: 0,
            metadata: ["model": model.ollamaId, "params": model.params]
        )

        let params = GenerationParams(
            prompt: prompt,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            prefillStepSize: nil,
            cacheEnabled: nil,
            gpuCacheLimitMb: nil,
            quantization: "q4_0"
        )

        return ModelBenchmarkResult(
            engine: "ollama",
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

    // MARK: - Helpers

    private func parseIteration(
        response: OllamaClient.GenerateResponse,
        iteration: Int,
        prompt: String
    ) -> IterationResult {
        let evalCount = response.evalCount ?? 0
        let evalDurationNs = response.evalDuration ?? 1
        let promptEvalDurationNs = response.promptEvalDuration ?? 0
        let totalDurationNs = response.totalDuration ?? 0

        let tokensPerSecond = evalCount > 0
            ? Double(evalCount) * 1e9 / Double(evalDurationNs)
            : 0

        let tpotMs = evalCount > 1
            ? Double(evalDurationNs) / Double(evalCount - 1) / 1e6
            : 0

        let ttftMs = Double(promptEvalDurationNs) / 1e6
        let e2eMs = Double(totalDurationNs) / 1e6

        return IterationResult(
            iteration: iteration,
            tokensPerSecond: tokensPerSecond,
            tpotMs: tpotMs,
            ttftMs: ttftMs,
            e2eMs: e2eMs,
            promptTokens: response.promptEvalCount ?? 0,
            outputTokens: evalCount,
            outputText: response.response,
            totalDurationMs: e2eMs
        )
    }

    private func nanosToMs(_ ns: Int64?) -> Double? {
        guard let ns = ns else { return nil }
        return Double(ns) / 1e6
    }
}
