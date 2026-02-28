import Foundation
import Octomil

/// Runs benchmark iterations directly against llama.cpp CLI (no Ollama HTTP layer).
/// Resolves GGUF model files from Ollama's blob store and invokes llama-cli as a subprocess.
public struct LlamaCppBenchmarkRunner: Sendable {
    private let binaryPath: String
    private let ollamaBlobDir: String

    public init(
        binaryPath: String = Self.defaultBinaryPath(),
        ollamaBlobDir: String = "\(NSHomeDirectory())/.ollama/models"
    ) {
        self.binaryPath = binaryPath
        self.ollamaBlobDir = ollamaBlobDir
    }

    /// Finds llama-cli binary — checks known paths.
    public static func defaultBinaryPath() -> String {
        let candidates = [
            "\(NSHomeDirectory())/Developer/Octomil/engines/llama.cpp/build/bin/llama-cli",
            "/opt/homebrew/bin/llama-cli",
            "/usr/local/bin/llama-cli",
        ]
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
            ?? candidates[0]
    }

    /// Whether llama-cli binary exists and is executable.
    public func isAvailable() -> Bool {
        FileManager.default.isExecutableFile(atPath: binaryPath)
    }

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
        // Resolve GGUF path from Ollama's manifest
        let ggufPath = try resolveGGUFPath(ollamaId: model.ollamaId)

        var allIterations: [IterationResult] = []
        var ttftCold: Double?

        // --- Cold run (includes model load) ---
        print("  [llama.cpp] Cold run...")
        let coldResult = try await runIteration(
            ggufPath: ggufPath, model: model, prompt: prompt,
            maxTokens: maxTokens, temperature: temperature, topP: topP, iteration: 0
        )
        ttftCold = coldResult.ttftMs

        // --- Warmup ---
        for w in 0..<warmup {
            print("  [llama.cpp] Warmup \(w + 1)/\(warmup)...")
            _ = try await runIteration(
                ggufPath: ggufPath, model: model, prompt: prompt,
                maxTokens: maxTokens, temperature: temperature, topP: topP, iteration: -1
            )
        }

        // --- Measured iterations (with optional auto-convergence) ---
        let minIterations = converge ? Swift.max(5, iterations / 2) : iterations
        for i in 0..<iterations {
            print("  [llama.cpp] Iteration \(i + 1)/\(iterations)...")
            let result = try await runIteration(
                ggufPath: ggufPath, model: model, prompt: prompt,
                maxTokens: maxTokens, temperature: temperature, topP: topP, iteration: i + 1
            )
            allIterations.append(result)

            if converge && allIterations.count >= minIterations {
                let toks = allIterations.map(\.tokensPerSecond)
                let mean = toks.reduce(0, +) / Double(toks.count)
                let variance = toks.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Double(toks.count - 1)
                let cv = mean > 0 ? variance.squareRoot() / mean : 1.0
                if cv < 0.05 {
                    print("  [llama.cpp] Converged at iteration \(i + 1) (CV=\(String(format: "%.1f", cv * 100))%)")
                    break
                }
            }
        }

        let stats = BenchmarkStats.compute(from: allIterations)

        let outputPreview: String? = allIterations.first.map {
            let text = $0.outputText.prefix(120)
            return text.count < $0.outputText.count ? String(text) + "..." : String(text)
        }

        let benchResult = BenchmarkResult(
            engineName: "llama.cpp",
            tokensPerSecond: stats.tokPerSec.mean,
            ttftMs: stats.ttftMs.mean,
            memoryMb: 0,
            metadata: ["model": model.ollamaId, "params": model.params]
        )

        let params = GenerationParams(
            prompt: prompt, maxTokens: maxTokens, temperature: temperature, topP: topP,
            prefillStepSize: nil, cacheEnabled: nil, gpuCacheLimitMb: nil, quantization: "q4_0"
        )

        return ModelBenchmarkResult(
            engine: "llama.cpp", model: model, result: benchResult, params: params,
            ttftColdMs: ttftCold, ttftWarmMs: stats.ttftMs.mean, tpotMs: stats.tpotMs.mean,
            e2eMs: stats.e2eMs.mean, kvCacheSpeedup: nil, iterationResults: allIterations,
            stats: stats, outputPreview: outputPreview, memBandwidthGBs: stats.memBandwidthGBs.mean,
            power: nil, energyPerTokenMJ: nil
        )
    }

    // MARK: - Single iteration via subprocess

    private func runIteration(
        ggufPath: String,
        model: ModelSpec,
        prompt: String,
        maxTokens: Int,
        temperature: Double,
        topP: Double,
        iteration: Int
    ) async throws -> IterationResult {
        let start = CFAbsoluteTimeGetCurrent()

        let process = Process()
        process.executableURL = URL(fileURLWithPath: binaryPath)
        process.arguments = [
            "-m", ggufPath,
            "-p", prompt,
            "-n", "\(maxTokens)",
            "--temp", "\(temperature)",
            "--top-p", "\(topP)",
            "-ngl", "99",
            "-fa", "on",
            "--single-turn",
            "--no-display-prompt",
            "--log-disable",
        ]

        let stdoutPipe = Pipe()
        process.standardOutput = stdoutPipe
        // Discard stderr to avoid pipe deadlock (Metal init logs can fill the buffer)
        process.standardError = FileHandle(forWritingAtPath: "/dev/null")
        process.standardInput = FileHandle.nullDevice

        try process.run()

        // Read stdout (stderr is discarded, so no deadlock risk)
        let stdoutData = stdoutPipe.fileHandleForReading.readDataToEndOfFile()

        process.waitUntilExit()

        let end = CFAbsoluteTimeGetCurrent()
        let e2eMs = (end - start) * 1000

        let stdout = String(data: stdoutData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            throw LlamaCppError.processExited(code: process.terminationStatus, stderr: "")
        }

        // Debug: print stdout size and whether timing was found
        if iteration >= 1 && iteration <= 1 {
            print("    [debug] stdout bytes=\(stdoutData.count), has_timing=\(stdout.contains("t/s"))")
            if !stdout.contains("t/s") {
                // Print last 200 chars for debugging
                print("    [debug] stdout tail: \(stdout.suffix(200))")
            }
        }

        // Parse "[ Prompt: 861.6 t/s | Generation: 90.5 t/s ]" from stdout
        let parsed = parseTimings(stdout: stdout)

        let genTokPerSec = parsed.generationTokPerSec
        let promptTokPerSec = parsed.promptTokPerSec

        // Extract output text: everything before the timing line
        let outputText = extractOutputText(stdout: stdout)
        // Estimate token count from generation speed and time
        let outputTokens = genTokPerSec > 0 ? Int(round(genTokPerSec * (e2eMs / 1000.0) * 0.8)) : maxTokens
        let ttftMs = promptTokPerSec > 0 ? 1000.0 / promptTokPerSec * 27 : 0 // ~27 prompt tokens
        let tpotMs = genTokPerSec > 0 ? 1000.0 / genTokPerSec : 0
        let bw = model.weightSizeBytes * genTokPerSec / 1e9

        return IterationResult(
            iteration: iteration,
            tokensPerSecond: genTokPerSec,
            tpotMs: tpotMs,
            ttftMs: ttftMs,
            e2eMs: e2eMs,
            promptTokens: 27, // approximate
            outputTokens: outputTokens,
            outputText: outputText,
            totalDurationMs: e2eMs,
            memBandwidthGBs: bw
        )
    }

    // MARK: - Output parsing

    private struct TimingParsed {
        let promptTokPerSec: Double
        let generationTokPerSec: Double
    }

    /// Parses "[ Prompt: 861.6 t/s | Generation: 90.5 t/s ]" from stdout.
    private func parseTimings(stdout: String) -> TimingParsed {
        // Match: Prompt: <number> t/s | Generation: <number> t/s
        let pattern = #"Prompt:\s+([\d.]+)\s+t/s\s+\|\s+Generation:\s+([\d.]+)\s+t/s"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                  in: stdout,
                  range: NSRange(stdout.startIndex..., in: stdout)
              )
        else {
            return TimingParsed(promptTokPerSec: 0, generationTokPerSec: 0)
        }

        let promptStr = String(stdout[Range(match.range(at: 1), in: stdout)!])
        let genStr = String(stdout[Range(match.range(at: 2), in: stdout)!])

        return TimingParsed(
            promptTokPerSec: Double(promptStr) ?? 0,
            generationTokPerSec: Double(genStr) ?? 0
        )
    }

    /// Extracts generated text from stdout (everything after the prompt echo, before timing line).
    private func extractOutputText(stdout: String) -> String {
        // The output is between the last "| " prefix and the timing line
        // Format: "| generated text here\n\n[ Prompt: ... ]"
        let lines = stdout.components(separatedBy: "\n")
        var outputLines: [String] = []
        var collecting = false

        for line in lines {
            if line.hasPrefix("| ") && !line.contains("t/s") {
                collecting = true
                outputLines.append(String(line.dropFirst(2)))
            } else if collecting && !line.contains("t/s") && !line.contains("Exiting") {
                outputLines.append(line)
            } else if line.contains("t/s") {
                break
            }
        }

        return outputLines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - GGUF resolution

    /// Resolves Ollama model ID (e.g. "llama3.2:1b") to the GGUF blob path.
    private func resolveGGUFPath(ollamaId: String) throws -> String {
        let parts = ollamaId.split(separator: ":")
        let modelName = String(parts[0])
        let tag = parts.count > 1 ? String(parts[1]) : "latest"

        let manifestPath = "\(ollamaBlobDir)/manifests/registry.ollama.ai/library/\(modelName)/\(tag)"

        guard let data = FileManager.default.contents(atPath: manifestPath) else {
            throw LlamaCppError.modelNotFound(ollamaId, manifestPath)
        }

        guard let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let layers = manifest["layers"] as? [[String: Any]]
        else {
            throw LlamaCppError.invalidManifest(manifestPath)
        }

        guard let modelLayer = layers.first(where: {
            ($0["mediaType"] as? String) == "application/vnd.ollama.image.model"
        }),
              let digest = modelLayer["digest"] as? String
        else {
            throw LlamaCppError.noModelLayer(manifestPath)
        }

        let blobName = digest.replacingOccurrences(of: ":", with: "-")
        let blobPath = "\(ollamaBlobDir)/blobs/\(blobName)"

        guard FileManager.default.fileExists(atPath: blobPath) else {
            throw LlamaCppError.blobNotFound(blobPath)
        }

        return blobPath
    }
}

enum LlamaCppError: Error, LocalizedError {
    case binaryNotFound(String)
    case processExited(code: Int32, stderr: String)
    case modelNotFound(String, String)
    case invalidManifest(String)
    case noModelLayer(String)
    case blobNotFound(String)

    var errorDescription: String? {
        switch self {
        case .binaryNotFound(let path):
            return "llama-cli not found at \(path)"
        case .processExited(let code, let stderr):
            return "llama-cli exited with code \(code): \(stderr.prefix(200))"
        case .modelNotFound(let id, let path):
            return "Model \(id) not found at \(path)"
        case .invalidManifest(let path):
            return "Invalid manifest at \(path)"
        case .noModelLayer(let path):
            return "No model layer in manifest at \(path)"
        case .blobNotFound(let path):
            return "GGUF blob not found at \(path)"
        }
    }
}
