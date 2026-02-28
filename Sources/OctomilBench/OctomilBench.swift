import ArgumentParser
import Foundation

@available(macOS 14.0, *)
@main
struct OctomilBench: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "octomil-bench",
        abstract: "Benchmark Octomil (MLX) vs Ollama across multiple models on Apple Silicon.",
        version: "1.0.0"
    )

    @Option(name: .long, help: "Comma-separated model filter (e.g. llama3.2:1b,qwen2.5:0.5b)")
    var models: String?

    @Option(name: .long, help: "Number of measured iterations per model per engine.")
    var iterations: Int = 3

    @Option(name: .long, help: "Number of warmup iterations (discarded).")
    var warmup: Int = 1

    @Option(name: .long, help: "Max tokens to generate per iteration.")
    var maxTokens: Int = 128

    @Option(name: .long, help: "Sampling temperature (0.0 for deterministic).")
    var temperature: Double = 0.0

    @Option(name: .long, help: "Nucleus sampling threshold.")
    var topP: Double = 0.9

    @Option(name: .long, help: "Custom prompt text.")
    var prompt: String = "Explain the theory of general relativity in simple terms."

    @Flag(name: .long, help: "Skip Ollama benchmarks (MLX only).")
    var skipOllama: Bool = false

    @Flag(name: .long, help: "Skip MLX benchmarks (Ollama only).")
    var skipMlx: Bool = false

    @Flag(name: .long, help: "Auto-pull missing Ollama models.")
    var pullMissing: Bool = false

    @Option(name: .long, help: "Output format: table, json, or both.")
    var output: OutputFormat = .both

    enum OutputFormat: String, ExpressibleByArgument, CaseIterable {
        case table
        case json
        case both
    }

    func run() async throws {
        let selectedModels: [ModelSpec]
        if let filter = models {
            let ids = filter.split(separator: ",").map(String.init)
            selectedModels = ModelMatrix.filter(ids: ids)
            if selectedModels.isEmpty {
                print("No models matched filter: \(filter)")
                print("Available models:")
                for m in ModelMatrix.all {
                    print("  \(m.ollamaId) — \(m.name) (\(m.params))")
                }
                throw ExitCode.failure
            }
        } else {
            selectedModels = ModelMatrix.all
        }

        let orchestrator = BenchmarkOrchestrator(
            models: selectedModels,
            iterations: iterations,
            warmup: warmup,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            prompt: prompt,
            skipOllama: skipOllama,
            skipMlx: skipMlx,
            pullMissing: pullMissing
        )

        let results = try await orchestrator.run()

        let config = RunConfig(
            iterations: iterations,
            warmup: warmup,
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            prompt: prompt
        )

        switch output {
        case .table:
            ReportFormatter.printTable(results, config: config)
        case .json:
            print(ReportFormatter.jsonReport(results, config: config))
        case .both:
            ReportFormatter.printTable(results, config: config)
            print("\n--- JSON Report ---")
            print(ReportFormatter.jsonReport(results, config: config))
        }
    }
}
