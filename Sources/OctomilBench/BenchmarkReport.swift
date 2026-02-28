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
    public let memBandwidthGBs: Double    // Effective memory bandwidth (GB/s)
}

// MARK: - Statistics

public struct MetricStats: Codable, Sendable {
    public let mean: Double
    public let stddev: Double
    public let min: Double
    public let max: Double
    public let p50: Double
    public let p95: Double
    public let ci95Lower: Double
    public let ci95Upper: Double
    public let n: Int

    public static func compute(from values: [Double]) -> MetricStats {
        guard !values.isEmpty else {
            return MetricStats(mean: 0, stddev: 0, min: 0, max: 0, p50: 0, p95: 0, ci95Lower: 0, ci95Upper: 0, n: 0)
        }
        let sorted = values.sorted()
        let n = Double(sorted.count)
        let mean = sorted.reduce(0, +) / n
        let variance = n > 1
            ? sorted.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / (n - 1)
            : 0
        let stddev = variance.squareRoot()
        let margin = 1.96 * stddev / n.squareRoot()
        return MetricStats(
            mean: mean,
            stddev: stddev,
            min: sorted.first!,
            max: sorted.last!,
            p50: percentile(sorted, 0.50),
            p95: percentile(sorted, 0.95),
            ci95Lower: mean - margin,
            ci95Upper: mean + margin,
            n: Int(n)
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

// MARK: - Welch's t-test

public struct SignificanceTest: Codable, Sendable {
    public let metric: String
    public let meanA: Double
    public let meanB: Double
    public let tStatistic: Double
    public let degreesOfFreedom: Double
    public let pValue: Double
    public let cohensD: Double
    public let significant: Bool      // p < 0.05

    /// Two-sample Welch's t-test (unequal variances).
    public static func welch(
        metric: String,
        a: [Double],
        b: [Double]
    ) -> SignificanceTest {
        let nA = Double(a.count)
        let nB = Double(b.count)
        let meanA = a.reduce(0, +) / nA
        let meanB = b.reduce(0, +) / nB
        let varA = a.map { ($0 - meanA) * ($0 - meanA) }.reduce(0, +) / (nA - 1)
        let varB = b.map { ($0 - meanB) * ($0 - meanB) }.reduce(0, +) / (nB - 1)

        let seA = varA / nA
        let seB = varB / nB
        let se = (seA + seB).squareRoot()

        let t = se > 0 ? (meanA - meanB) / se : 0

        // Welch-Satterthwaite degrees of freedom
        let num = (seA + seB) * (seA + seB)
        let denA = nA > 1 ? (seA * seA) / (nA - 1) : 0
        let denB = nB > 1 ? (seB * seB) / (nB - 1) : 0
        let df = (denA + denB) > 0 ? num / (denA + denB) : 1

        // Cohen's d (pooled stddev)
        let pooledVar = ((nA - 1) * varA + (nB - 1) * varB) / (nA + nB - 2)
        let d = pooledVar > 0 ? (meanA - meanB) / pooledVar.squareRoot() : 0

        // Approximate p-value from t-distribution using regularized incomplete beta
        let p = tDistPValue(t: abs(t), df: df)

        return SignificanceTest(
            metric: metric,
            meanA: meanA,
            meanB: meanB,
            tStatistic: t,
            degreesOfFreedom: df,
            pValue: p,
            cohensD: d,
            significant: p < 0.05
        )
    }

    /// Two-tailed p-value approximation for t-distribution.
    /// Uses the approximation: p ≈ 2 * (1 - Φ(|t| * sqrt(df/(df-2+t²))))
    /// which is accurate for df > 3.
    private static func tDistPValue(t: Double, df: Double) -> Double {
        guard df > 0, t.isFinite else { return 1.0 }
        // For large df, t-dist ≈ normal
        if df > 100 {
            return 2 * normalCDF(-abs(t))
        }
        // Hill's approximation
        let x = df / (df + t * t)
        let p = regularizedIncompleteBeta(a: df / 2, b: 0.5, x: x)
        return p
    }

    /// Standard normal CDF via error function approximation (Abramowitz & Stegun 7.1.26).
    private static func normalCDF(_ x: Double) -> Double {
        let a1 = 0.254829592
        let a2 = -0.284496736
        let a3 = 1.421413741
        let a4 = -1.453152027
        let a5 = 1.061405429
        let p = 0.3275911
        let sign: Double = x < 0 ? -1 : 1
        let absX = abs(x) / 2.0.squareRoot()
        let t = 1.0 / (1.0 + p * absX)
        let y = 1.0 - (((((a5 * t + a4) * t) + a3) * t + a2) * t + a1) * t * exp(-absX * absX)
        return 0.5 * (1.0 + sign * y)
    }

    /// Regularized incomplete beta function via continued fraction (Lentz's method).
    private static func regularizedIncompleteBeta(a: Double, b: Double, x: Double) -> Double {
        guard x > 0, x < 1 else {
            return x <= 0 ? 0 : 1
        }
        let lnBeta = lgamma(a) + lgamma(b) - lgamma(a + b)
        let front = exp(log(x) * a + log(1 - x) * b - lnBeta)

        // Use Lentz's continued fraction
        var f = 1.0
        var c = 1.0
        var d = 1.0 - (a + b) * x / (a + 1)
        if abs(d) < 1e-30 { d = 1e-30 }
        d = 1.0 / d
        f = d

        for m in 1...200 {
            let mf = Double(m)
            // Even step
            var num = mf * (b - mf) * x / ((a + 2 * mf - 1) * (a + 2 * mf))
            d = 1.0 + num * d
            if abs(d) < 1e-30 { d = 1e-30 }
            c = 1.0 + num / c
            if abs(c) < 1e-30 { c = 1e-30 }
            d = 1.0 / d
            f *= c * d

            // Odd step
            num = -(a + mf) * (a + b + mf) * x / ((a + 2 * mf) * (a + 2 * mf + 1))
            d = 1.0 + num * d
            if abs(d) < 1e-30 { d = 1e-30 }
            c = 1.0 + num / c
            if abs(c) < 1e-30 { c = 1e-30 }
            d = 1.0 / d
            let delta = c * d
            f *= delta

            if abs(delta - 1.0) < 1e-10 { break }
        }

        return front * f / a
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
    public let memBandwidthGBs: Double?
    public let power: PowerReading?
    public let energyPerTokenMJ: Double?    // millijoules per token
}

public struct BenchmarkStats: Codable, Sendable {
    public let tokPerSec: MetricStats
    public let tpotMs: MetricStats
    public let ttftMs: MetricStats
    public let e2eMs: MetricStats
    public let memBandwidthGBs: MetricStats

    public static func compute(from iterations: [IterationResult]) -> BenchmarkStats {
        BenchmarkStats(
            tokPerSec: MetricStats.compute(from: iterations.map(\.tokensPerSecond)),
            tpotMs: MetricStats.compute(from: iterations.map(\.tpotMs)),
            ttftMs: MetricStats.compute(from: iterations.map(\.ttftMs)),
            e2eMs: MetricStats.compute(from: iterations.map(\.e2eMs)),
            memBandwidthGBs: MetricStats.compute(from: iterations.map(\.memBandwidthGBs))
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
    public let significanceTests: [SignificanceTest]?
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
        let hasPower = results.contains { $0.power != nil }
        let w = 160 + (hasPower ? 30 : 0)
        let divider = String(repeating: "=", count: w)
        let thinDivider = String(repeating: "-", count: w)

        print(divider)
        var headerRow = "\(pad("Model", 20))| \(pad("Engine", 9))| \(pad("Tok/s", 6, left: false)) | \(pad("\u{00B1}stddev", 7, left: false)) | \(pad("TPOT ms", 7, left: false)) | \(pad("TTFT Warm", 9, left: false)) | \(pad("TTFT Cold", 9, left: false)) | \(pad("E2E ms", 8, left: false)) | \(pad("BW GB/s", 7, left: false)) | \(pad("Tokens", 8, left: false)) | \(pad("KV Cache", 8, left: false)) | \(pad("Mem MB", 8, left: false))"
        if hasPower {
            headerRow += " | \(pad("Power W", 7, left: false)) | \(pad("mJ/tok", 7, left: false))"
        }
        headerRow += " | \(pad("Status", 6, left: false))"
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
            let bw = r.memBandwidthGBs.map { fmtF($0) } ?? "N/A"
            let status = r.result.ok ? "OK" : "FAIL"

            var row = "\(pad(String(r.model.name.prefix(20)), 20))| \(pad(r.engine, 9))| \(pad(fmtF(r.result.tokensPerSecond), 6, left: false)) | \(pad(tokStddev, 7, left: false)) | \(pad(fmtF(r.tpotMs ?? 0), 7, left: false)) | \(pad(fmtF(r.ttftWarmMs ?? 0), 9, left: false)) | \(pad(fmtF(r.ttftColdMs ?? 0), 9, left: false)) | \(pad(fmtF(r.e2eMs ?? 0), 8, left: false)) | \(pad(bw, 7, left: false)) | \(pad(totalTokens, 8, left: false)) | \(pad(kvCache, 8, left: false)) | \(pad(mem, 8, left: false))"
            if hasPower {
                let pw = r.power.map { fmtF($0.totalW) } ?? "N/A"
                let energy = r.energyPerTokenMJ.map { fmtF($0) } ?? "N/A"
                row += " | \(pad(pw, 7, left: false)) | \(pad(energy, 7, left: false))"
            }
            row += " | \(pad(status, 6, left: false))"
            print(row)
        }

        print(divider)

        // Per-metric statistics
        if config.iterations > 1 {
            print()
            print("Detailed Statistics (p50 / p95 / stddev):")
            for r in results {
                guard let s = r.stats else { continue }
                print("  \(r.model.name) [\(r.engine)] (n=\(s.tokPerSec.n)):")
                print("    Tok/s:   \(fmtF(s.tokPerSec.mean)) [\(fmtF(s.tokPerSec.ci95Lower)), \(fmtF(s.tokPerSec.ci95Upper))]  p50=\(fmtF(s.tokPerSec.p50))  p95=\(fmtF(s.tokPerSec.p95))  \u{00B1}\(fmtF(s.tokPerSec.stddev))")
                print("    TPOT:    \(fmtF(s.tpotMs.mean))ms [\(fmtF(s.tpotMs.ci95Lower)), \(fmtF(s.tpotMs.ci95Upper))]  p50=\(fmtF(s.tpotMs.p50))ms  \u{00B1}\(fmtF(s.tpotMs.stddev))ms")
                print("    TTFT:    \(fmtF(s.ttftMs.mean))ms [\(fmtF(s.ttftMs.ci95Lower)), \(fmtF(s.ttftMs.ci95Upper))]  p50=\(fmtF(s.ttftMs.p50))ms  \u{00B1}\(fmtF(s.ttftMs.stddev))ms")
                print("    E2E:     \(fmtF(s.e2eMs.mean))ms [\(fmtF(s.e2eMs.ci95Lower)), \(fmtF(s.e2eMs.ci95Upper))]  p50=\(fmtF(s.e2eMs.p50))ms  \u{00B1}\(fmtF(s.e2eMs.stddev))ms")
                print("    BW:      \(fmtF(s.memBandwidthGBs.mean)) GB/s [\(fmtF(s.memBandwidthGBs.ci95Lower)), \(fmtF(s.memBandwidthGBs.ci95Upper))]  \u{00B1}\(fmtF(s.memBandwidthGBs.stddev))")
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
        let grouped = Dictionary(grouping: results) { $0.model.name }

        for (name, group) in grouped.sorted(by: { $0.key < $1.key }) {
            guard group.count >= 2 else { continue }
            let sorted = group.sorted { $0.result.tokensPerSecond > $1.result.tokensPerSecond }
            let winner = sorted[0]
            let loser = sorted[1]

            let winIters = winner.iterationResults
            let loseIters = loser.iterationResults
            guard winIters.count >= 2, loseIters.count >= 2 else { continue }

            print()
            print("Statistical Comparison: \(name)")
            print(String(repeating: "-", count: 50))

            let speedup = loser.result.tokensPerSecond > 0
                ? winner.result.tokensPerSecond / loser.result.tokensPerSecond : 0

            let tests = [
                SignificanceTest.welch(
                    metric: "Tok/s",
                    a: winIters.map(\.tokensPerSecond),
                    b: loseIters.map(\.tokensPerSecond)
                ),
                SignificanceTest.welch(
                    metric: "TPOT (ms)",
                    a: winIters.map(\.tpotMs),
                    b: loseIters.map(\.tpotMs)
                ),
                SignificanceTest.welch(
                    metric: "E2E (ms)",
                    a: winIters.map(\.e2eMs),
                    b: loseIters.map(\.e2eMs)
                ),
            ]

            print("  Winner: \(winner.engine) (\(fmtF(speedup))x faster tok/s)")
            print()
            print("  \(pad("Metric", 12))| \(pad(winner.engine, 10))| \(pad(loser.engine, 10))| \(pad("t-stat", 8, left: false)) | \(pad("df", 5, left: false)) | \(pad("p-value", 10, left: false)) | \(pad("Cohen's d", 9, left: false)) | Sig?")
            print("  \(String(repeating: "-", count: 80))")

            for t in tests {
                let pStr = t.pValue < 0.001
                    ? "<0.001"
                    : fmtF(t.pValue, 4)
                let sig = t.significant ? "YES" : "no"
                let dMag: String
                let absD = abs(t.cohensD)
                if absD >= 0.8 { dMag = " (large)" }
                else if absD >= 0.5 { dMag = " (medium)" }
                else if absD >= 0.2 { dMag = " (small)" }
                else { dMag = " (negligible)" }

                print("  \(pad(t.metric, 12))| \(pad(fmtF(t.meanA), 10, left: false))| \(pad(fmtF(t.meanB), 10, left: false))| \(pad(fmtF(t.tStatistic, 2), 8, left: false)) | \(pad(fmtF(t.degreesOfFreedom, 1), 5, left: false)) | \(pad(pStr, 10, left: false)) | \(pad(fmtF(absD, 2), 6, left: false))\(dMag) | \(sig)")
            }

            print()
            if tests.allSatisfy({ $0.significant }) {
                print("  All metrics statistically significant (p < 0.05)")
            } else {
                let notSig = tests.filter { !$0.significant }.map(\.metric)
                print("  Not significant: \(notSig.joined(separator: ", "))")
            }
        }
    }

    public static func jsonReport(_ results: [ModelBenchmarkResult], config: RunConfig) -> String {
        let tests = computeSignificanceTests(results)
        let report = BenchmarkReport(
            version: "1.0.0",
            timestamp: ISO8601DateFormatter().string(from: Date()),
            system: SystemInfo.collect(),
            config: config,
            results: results,
            significanceTests: tests.isEmpty ? nil : tests
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(report) else { return "{}" }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    private static func computeSignificanceTests(_ results: [ModelBenchmarkResult]) -> [SignificanceTest] {
        var tests: [SignificanceTest] = []
        let grouped = Dictionary(grouping: results) { $0.model.name }
        for (_, group) in grouped.sorted(by: { $0.key < $1.key }) {
            guard group.count >= 2 else { continue }
            let a = group[0].iterationResults
            let b = group[1].iterationResults
            guard a.count >= 2, b.count >= 2 else { continue }
            tests.append(SignificanceTest.welch(metric: "tok_per_sec", a: a.map(\.tokensPerSecond), b: b.map(\.tokensPerSecond)))
            tests.append(SignificanceTest.welch(metric: "tpot_ms", a: a.map(\.tpotMs), b: b.map(\.tpotMs)))
            tests.append(SignificanceTest.welch(metric: "e2e_ms", a: a.map(\.e2eMs), b: b.map(\.e2eMs)))
        }
        return tests
    }
}
