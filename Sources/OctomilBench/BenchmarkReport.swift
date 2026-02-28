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

// MARK: - Statistics

public struct MetricStats: Codable, Sendable {
    public let mean: Double
    public let stddev: Double
    public let min: Double
    public let max: Double
    public let p50: Double
    public let p95: Double

    public static func compute(from values: [Double]) -> MetricStats {
        guard !values.isEmpty else {
            return MetricStats(mean: 0, stddev: 0, min: 0, max: 0, p50: 0, p95: 0)
        }
        let sorted = values.sorted()
        let n = Double(sorted.count)
        let mean = sorted.reduce(0, +) / n
        let variance = sorted.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / n
        let stddev = variance.squareRoot()
        return MetricStats(
            mean: mean,
            stddev: stddev,
            min: sorted.first!,
            max: sorted.last!,
            p50: percentile(sorted, 0.50),
            p95: percentile(sorted, 0.95)
        )
    }

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double {
        guard sorted.count > 1 else { return sorted.first ?? 0 }
        let index = p * Double(sorted.count - 1)
        let lower = Int(index)
        let upper = Swift.min(lower + 1, sorted.count - 1)
        let frac = index - Double(lower)
        return sorted[lower] * (1 - frac) + sorted[upper] * frac
    }
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
    public let stats: BenchmarkStats?
    public let outputPreview: String?
}

public struct BenchmarkStats: Codable, Sendable {
    public let tokPerSec: MetricStats
    public let tpotMs: MetricStats
    public let ttftMs: MetricStats
    public let e2eMs: MetricStats

    public static func compute(from iterations: [IterationResult]) -> BenchmarkStats {
        BenchmarkStats(
            tokPerSec: MetricStats.compute(from: iterations.map(\.tokensPerSecond)),
            tpotMs: MetricStats.compute(from: iterations.map(\.tpotMs)),
            ttftMs: MetricStats.compute(from: iterations.map(\.ttftMs)),
            e2eMs: MetricStats.compute(from: iterations.map(\.e2eMs))
        )
    }
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
        print()
        let header = "Octomil Benchmark Tool v1.0.0"
        print(header)
        print(String(repeating: "=", count: header.count))
        print("System: \(SystemInfo.collect().summary)")
        let prompt = config.prompt
        let truncatedPrompt = prompt.count > 80 ? String(prompt.prefix(80)) + "..." : prompt
        print("Prompt: \"\(truncatedPrompt)\"")
        print("Config: \(config.iterations) iterations, \(config.warmup) warmup, \(config.maxTokens) max tokens, temp=\(config.temperature), topP=\(config.topP)")
        print()

        // Main results table
        let divider = String(repeating: "=", count: 130)
        let thinDivider = String(repeating: "-", count: 130)

        print(divider)
        let headerRow = "\(pad("Model", 20))| \(pad("Engine", 9))| \(pad("Tok/s", 6, left: false)) | \(pad("\u{00B1}stddev", 7, left: false)) | \(pad("TPOT ms", 7, left: false)) | \(pad("TTFT Warm", 9, left: false)) | \(pad("TTFT Cold", 9, left: false)) | \(pad("E2E ms", 8, left: false)) | \(pad("Tokens", 8, left: false)) | \(pad("KV Cache", 8, left: false)) | \(pad("Mem MB", 8, left: false)) | \(pad("Status", 6, left: false))"
        print(headerRow)
        print(divider)

        var currentModel = ""
        for r in results {
            if r.model.name != currentModel && !currentModel.isEmpty {
                print(thinDivider)
            }
            currentModel = r.model.name

            let tokStddev = r.stats.map { fmtF($0.tokPerSec.stddev) } ?? "N/A"
            let totalTokens = r.iterationResults.first.map { "\($0.outputTokens)/\($0.promptTokens)" } ?? "N/A"
            let kvCache = r.kvCacheSpeedup.map { String(format: "%.2fx", $0) } ?? "N/A"
            let mem = r.result.memoryMb > 0 ? fmtF(r.result.memoryMb) : "N/A"
            let status = r.result.ok ? "OK" : "FAIL"

            let row = "\(pad(String(r.model.name.prefix(20)), 20))| \(pad(r.engine, 9))| \(pad(fmtF(r.result.tokensPerSecond), 6, left: false)) | \(pad(tokStddev, 7, left: false)) | \(pad(fmtF(r.tpotMs ?? 0), 7, left: false)) | \(pad(fmtF(r.ttftWarmMs ?? 0), 9, left: false)) | \(pad(fmtF(r.ttftColdMs ?? 0), 9, left: false)) | \(pad(fmtF(r.e2eMs ?? 0), 8, left: false)) | \(pad(totalTokens, 8, left: false)) | \(pad(kvCache, 8, left: false)) | \(pad(mem, 8, left: false)) | \(pad(status, 6, left: false))"
            print(row)
        }

        print(divider)

        // Per-metric statistics
        if config.iterations > 1 {
            print()
            print("Detailed Statistics (p50 / p95 / stddev):")
            for r in results {
                guard let s = r.stats else { continue }
                print("  \(r.model.name) [\(r.engine)]:")
                print("    Tok/s:   p50=\(fmtF(s.tokPerSec.p50))  p95=\(fmtF(s.tokPerSec.p95))  \u{00B1}\(fmtF(s.tokPerSec.stddev))  range=[\(fmtF(s.tokPerSec.min))-\(fmtF(s.tokPerSec.max))]")
                print("    TPOT:    p50=\(fmtF(s.tpotMs.p50))ms  p95=\(fmtF(s.tpotMs.p95))ms  \u{00B1}\(fmtF(s.tpotMs.stddev))ms")
                print("    TTFT:    p50=\(fmtF(s.ttftMs.p50))ms  p95=\(fmtF(s.ttftMs.p95))ms  \u{00B1}\(fmtF(s.ttftMs.stddev))ms")
                print("    E2E:     p50=\(fmtF(s.e2eMs.p50))ms  p95=\(fmtF(s.e2eMs.p95))ms  \u{00B1}\(fmtF(s.e2eMs.stddev))ms")
            }
        }

        // Output text preview
        let previews = results.filter { $0.outputPreview != nil }
        if !previews.isEmpty {
            print()
            print("Output Preview (first 120 chars):")
            for r in previews {
                print("  [\(r.engine)] \(r.outputPreview!)")
            }
        }

        printSummary(results)
        print()
        let promptTokens = results.first?.iterationResults.first?.promptTokens ?? 0
        print("Parameters: prompt_tokens=\(promptTokens), max_tokens=\(config.maxTokens), temp=\(config.temperature), top_p=\(config.topP), mlx_prefill_step=4096, mlx_gpu_cache=2048MB")
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
            print("  \(name): \(winner.engine) wins (\(String(format: "%.1f", speedup))x faster tok/s, \(String(format: "%.1f", tpotRatio))x lower TPOT)")
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
