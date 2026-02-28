import Foundation
import Octomil

// MARK: - Iteration Result

public struct IterationResult: Codable, Sendable {
    public let iteration: Int
    public let tokensPerSecond: Double
    public let tpotMs: Double
    public let ttftMs: Double
    public let e2eMs: Double
    public let promptTokens: Int
    public let outputTokens: Int
    public let outputText: String
    public let totalDurationMs: Double
}

// MARK: - Generation Parameters

public struct GenerationParams: Codable, Sendable {
    public let prompt: String
    public let maxTokens: Int
    public let temperature: Double
    public let topP: Double
    public let prefillStepSize: Int?
    public let cacheEnabled: Bool?
    public let gpuCacheLimitMb: Int?
    public let quantization: String
}

// MARK: - Model Benchmark Result

public struct ModelBenchmarkResult: Codable, Sendable {
    public let engine: String
    public let model: ModelSpec
    public let result: BenchmarkResult
    public let params: GenerationParams
    public let ttftColdMs: Double?
    public let ttftWarmMs: Double?
    public let tpotMs: Double?
    public let e2eMs: Double?
    public let kvCacheSpeedup: Double?
    public let iterationResults: [IterationResult]
}

// MARK: - Full Report

public struct BenchmarkReport: Codable, Sendable {
    public let version: String
    public let timestamp: String
    public let system: SystemInfo
    public let config: RunConfig
    public let results: [ModelBenchmarkResult]
}

public struct RunConfig: Codable, Sendable {
    public let iterations: Int
    public let warmup: Int
    public let maxTokens: Int
    public let temperature: Double
    public let topP: Double
    public let prompt: String
}

// MARK: - Table Formatter

public enum ReportFormatter {

    private static func pad(_ s: String, _ width: Int, left: Bool = true) -> String {
        if s.count >= width { return String(s.prefix(width)) }
        let padding = String(repeating: " ", count: width - s.count)
        return left ? s + padding : padding + s
    }

    private static func fmtF(_ v: Double, _ decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f", v)
    }

    public static func printTable(_ results: [ModelBenchmarkResult], config: RunConfig) {
        let prompt = config.prompt
        let promptTokenCount = prompt.split(separator: " ").count

        print()
        let header = "Octomil Benchmark Tool v1.0.0"
        print(header)
        print(String(repeating: "=", count: header.count))
        print("System: \(SystemInfo.collect().summary)")
        let truncatedPrompt = prompt.count > 80 ? String(prompt.prefix(80)) + "..." : prompt
        print("Prompt: \"\(truncatedPrompt)\"")
        print("Config: \(config.iterations) iterations, \(config.warmup) warmup, \(config.maxTokens) max tokens, temp=\(config.temperature), topP=\(config.topP)")
        print()

        let divider = String(repeating: "=", count: 122)
        let thinDivider = String(repeating: "-", count: 122)

        print(divider)
        let headerRow = "\(pad("Model", 20))| \(pad("Engine", 9))| \(pad("Tok/s", 6, left: false)) | \(pad("TPOT ms", 7, left: false)) | \(pad("TTFT Warm", 9, left: false)) | \(pad("TTFT Cold", 9, left: false)) | \(pad("E2E ms", 8, left: false)) | \(pad("Tokens", 6, left: false)) | \(pad("KV Cache", 8, left: false)) | \(pad("Mem MB", 8, left: false)) | \(pad("Status", 6, left: false))"
        print(headerRow)
        print(divider)

        var currentModel = ""
        for r in results {
            if r.model.name != currentModel && !currentModel.isEmpty {
                print(thinDivider)
            }
            currentModel = r.model.name

            let totalTokens = r.iterationResults.first.map { "\($0.outputTokens)/\($0.promptTokens)" } ?? "N/A"
            let kvCache = r.kvCacheSpeedup.map { String(format: "%.2fx", $0) } ?? "N/A"
            let mem = r.result.memoryMb > 0 ? fmtF(r.result.memoryMb) : "N/A"
            let status = r.result.ok ? "OK" : "FAIL"

            let row = "\(pad(String(r.model.name.prefix(20)), 20))| \(pad(r.engine, 9))| \(pad(fmtF(r.result.tokensPerSecond), 6, left: false)) | \(pad(fmtF(r.tpotMs ?? 0), 7, left: false)) | \(pad(fmtF(r.ttftWarmMs ?? 0), 9, left: false)) | \(pad(fmtF(r.ttftColdMs ?? 0), 9, left: false)) | \(pad(fmtF(r.e2eMs ?? 0), 8, left: false)) | \(pad(totalTokens, 6, left: false)) | \(pad(kvCache, 8, left: false)) | \(pad(mem, 8, left: false)) | \(pad(status, 6, left: false))"
            print(row)
        }

        print(divider)
        printSummary(results)
        print()
        print("Parameters: prompt_len=~\(promptTokenCount), max_tokens=\(config.maxTokens), temp=\(config.temperature), top_p=\(config.topP), mlx_prefill_step=4096, mlx_gpu_cache=2048MB")
    }

    private static func printSummary(_ results: [ModelBenchmarkResult]) {
        print()
        print("Summary (tok/s winner per model):")

        let grouped = Dictionary(grouping: results) { $0.model.name }
        for (name, group) in grouped.sorted(by: { $0.key < $1.key }) {
            guard group.count >= 2 else { continue }
            let sorted = group.sorted { $0.result.tokensPerSecond > $1.result.tokensPerSecond }
            let winner = sorted[0]
            let loser = sorted[1]
            guard loser.result.tokensPerSecond > 0 else { continue }
            let speedup = winner.result.tokensPerSecond / loser.result.tokensPerSecond
            let tpotRatio = (loser.tpotMs ?? 1) / (winner.tpotMs ?? 1)
            print("  \(name): \(winner.engine) wins (\(String(format: "%.1f", speedup))x faster, \(String(format: "%.1f", tpotRatio))x lower TPOT)")
        }
    }

    public static func jsonReport(_ results: [ModelBenchmarkResult], config: RunConfig) -> String {
        let report = BenchmarkReport(
            version: "1.0.0",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            system: SystemInfo.collect(),
            config: config,
            results: results
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }
}
