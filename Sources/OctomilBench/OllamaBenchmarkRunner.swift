import Foundation
import Octomil

/// Runs cold/warm/cache benchmark iterations against Ollama via /api/chat.
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
        let coldResponse = try await client.chat(
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
            _ = try await client.chat(
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
            let response = try await client.chat(
                model: model.ollamaId,
                prompt: prompt,
                maxTokens: maxTokens,
                temperature: temperature,
                topP: topP
            )
            allIterations.append(parseIteration(response: response, iteration: i + 1))
        }

        // --- KV cache measurement (Ollama server-side prompt cache) ---
        print("  [ollama] KV cache test (run 1)...")
        let cache1 = try await client.chat(
            model: model.ollamaId,
            prompt: prompt,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP
        )
        kvCacheTtft1 = nanosToMs(cache1.promptEvalDuration)

        print("  [ollama] KV cache test (run 2, server-side cache)...")
        let cache2 = try await client.chat(
            model: model.ollamaId,
            prompt: prompt,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP
        )
        kvCacheTtft2 = nanosToMs(cache2.promptEvalDuration)

        // Compute stats
        let stats = BenchmarkStats.compute(from: allIterations)

        let kvSpeedup: Double? = {
            guard let t1 = kvCacheTtft1, let t2 = kvCacheTtft2, t2 > 0 else { return nil }
            return t1 / t2
        }()

        let outputPreview: String? = allIterations.first.map {
            let text = $0.outputText.prefix(120)
            return text.count < $0.outputText.count
                ? String(text) + "..."
                : String(text)
        }

        let benchResult = BenchmarkResult(
            engineName: "ollama",
            tokensPerSecond: stats.tokPerSec.mean,
            ttftMs: stats.ttftMs.mean,
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
            ttftWarmMs: stats.ttftMs.mean,
            tpotMs: stats.tpotMs.mean,
            e2eMs: stats.e2eMs.mean,
            kvCacheSpeedup: kvSpeedup,
            iterationResults: allIterations,
            stats: stats,
            outputPreview: outputPreview
        )
    }

    // MARK: - Helpers

    private func parseIteration(
        response: OllamaClient.ChatResponse,
        iteration: Int
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
            outputText: response.message.content,
            totalDurationMs: e2eMs
        )
    }

    private func nanosToMs(_ ns: Int64?) -> Double? {
        guard let ns = ns else { return nil }
        return Double(ns) / 1e6
    }
}
