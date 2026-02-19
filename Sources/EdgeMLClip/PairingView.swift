#if os(iOS)
import SwiftUI
import EdgeML

/// Main view for the EdgeML App Clip pairing flow.
///
/// Displays different states as the pairing progresses:
/// - Connecting to the server
/// - Waiting for model deployment
/// - Downloading the model
/// - Running benchmarks
/// - Displaying results
public struct PairingView: View {

    @StateObject private var viewModel = PairingViewModel()

    public init() {}

    public var body: some View {
        NavigationView {
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                VStack(spacing: 24) {
                    switch viewModel.state {
                    case .idle:
                        idleView

                    case .connecting:
                        connectingView

                    case .waiting(let modelName):
                        waitingView(modelName: modelName)

                    case .downloading(let progress):
                        downloadingView(progress: progress)

                    case .benchmarking(let metrics):
                        benchmarkingView(metrics: metrics)

                    case .complete(let report):
                        completeView(report: report)

                    case .error(let message):
                        errorView(message: message)
                    }
                }
                .padding()
            }
            .navigationTitle("EdgeML")
            .navigationBarTitleDisplayMode(.inline)
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                handleIncomingURL(activity)
            }
            .onOpenURL { url in
                handleURL(url)
            }
        }
    }

    // MARK: - State Views

    private var idleView: some View {
        VStack(spacing: 16) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("EdgeML Pairing")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Scan the QR code from the EdgeML dashboard to begin.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private var connectingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Connecting to EdgeML...")
                .font(.title3)
                .fontWeight(.medium)

            Text("Establishing connection with the server.")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }

    private func waitingView(modelName: String) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Waiting for deployment...")
                .font(.title3)
                .fontWeight(.medium)

            HStack {
                Image(systemName: "cube.box")
                    .foregroundColor(.accentColor)
                Text(modelName)
                    .fontWeight(.medium)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(Color.accentColor.opacity(0.1))
            .cornerRadius(8)

            Text("The server is preparing an optimized model for your device.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    private func downloadingView(progress: Double) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundColor(.accentColor)

            Text("Downloading Model")
                .font(.title3)
                .fontWeight(.medium)

            ProgressView(value: progress, total: 1.0)
                .progressViewStyle(.linear)
                .frame(maxWidth: 280)

            Text("\(Int(progress * 100))%")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func benchmarkingView(metrics: LiveMetrics) -> some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)

            Text("Running performance tests...")
                .font(.title3)
                .fontWeight(.medium)

            if metrics.currentInference > 0 {
                VStack(spacing: 8) {
                    HStack {
                        Text("Inference")
                            .foregroundColor(.secondary)
                        Spacer()
                        Text("\(metrics.currentInference)/\(metrics.totalInferences)")
                    }

                    if let latency = metrics.lastLatencyMs {
                        HStack {
                            Text("Last latency")
                                .foregroundColor(.secondary)
                            Spacer()
                            Text(String(format: "%.1f ms", latency))
                        }
                    }
                }
                .font(.subheadline)
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
        }
    }

    private func completeView(report: BenchmarkReport) -> some View {
        ScrollView {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundColor(.green)

                    Text("Benchmark Complete")
                        .font(.title2)
                        .fontWeight(.semibold)
                }

                // Model + Device Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        row(label: "Model", value: report.modelName)
                        Divider()
                        row(label: "Device", value: report.deviceName)
                        row(label: "Chip", value: report.chipFamily)
                        row(label: "RAM", value: String(format: "%.1f GB", report.ramGB))
                        row(label: "OS", value: "iOS \(report.osVersion)")
                    }
                } label: {
                    Label("Configuration", systemImage: "cpu")
                }

                // Performance Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        row(label: "Tokens/sec", value: String(format: "%.1f", report.tokensPerSecond))
                        row(label: "TTFT", value: String(format: "%.1f ms", report.ttftMs))
                        row(label: "TPOT", value: String(format: "%.1f ms", report.tpotMs))
                        Divider()
                        row(label: "p50 Latency", value: String(format: "%.1f ms", report.p50LatencyMs))
                        row(label: "p95 Latency", value: String(format: "%.1f ms", report.p95LatencyMs))
                        row(label: "p99 Latency", value: String(format: "%.1f ms", report.p99LatencyMs))
                    }
                } label: {
                    Label("Performance", systemImage: "speedometer")
                }

                // Resources Card
                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        row(label: "Memory Peak", value: formatBytes(report.memoryPeakBytes))
                        row(label: "Model Load", value: String(format: "%.0f ms", report.modelLoadTimeMs))
                        row(label: "Cold Inference", value: String(format: "%.1f ms", report.coldInferenceMs))
                        row(label: "Warm Inference", value: String(format: "%.1f ms", report.warmInferenceMs))
                        row(label: "Inference Count", value: "\(report.inferenceCount)")
                        if let batteryLevel = report.batteryLevel {
                            row(label: "Battery", value: String(format: "%.0f%%", batteryLevel * 100))
                        }
                        if let thermalState = report.thermalState {
                            row(label: "Thermal", value: thermalState.capitalized)
                        }
                    }
                } label: {
                    Label("Resources", systemImage: "chart.bar")
                }

                // Share Button
                if let shareText = viewModel.shareText {
                    ShareLink(item: shareText) {
                        Label("Share Results", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }
        }
    }

    private func errorView(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.red)

            Text("Pairing Failed")
                .font(.title3)
                .fontWeight(.medium)

            Text(message)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button("Try Again") {
                viewModel.reset()
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Helpers

    private func row(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }

    private func formatBytes(_ bytes: Int) -> String {
        let mb = Double(bytes) / (1024 * 1024)
        if mb >= 1024 {
            return String(format: "%.1f GB", mb / 1024)
        }
        return String(format: "%.1f MB", mb)
    }

    // MARK: - URL Handling

    private func handleIncomingURL(_ activity: NSUserActivity) {
        guard let url = activity.webpageURL else { return }
        handleURL(url)
    }

    private func handleURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true),
              let codeItem = components.queryItems?.first(where: { $0.name == "code" }),
              let code = codeItem.value else {
            viewModel.state = .error("Invalid pairing URL. Missing code parameter.")
            return
        }

        // Extract server URL from the QR URL host if available
        var serverURL = URL(string: "https://api.edgeml.ai")!
        if let hostItem = components.queryItems?.first(where: { $0.name == "server" }),
           let serverString = hostItem.value,
           let parsedURL = URL(string: serverString) {
            serverURL = parsedURL
        }

        viewModel.startPairing(code: code, serverURL: serverURL)
    }
}

// MARK: - Live Metrics

/// Live metrics displayed during benchmarking.
struct LiveMetrics {
    var currentInference: Int = 0
    var totalInferences: Int = 11  // 1 cold + 10 warm
    var lastLatencyMs: Double?
}

// MARK: - Pairing State

/// States of the pairing flow.
enum PairingState {
    case idle
    case connecting
    case waiting(modelName: String)
    case downloading(progress: Double)
    case benchmarking(metrics: LiveMetrics)
    case complete(report: BenchmarkReport)
    case error(message: String)
}

// MARK: - View Model

/// View model driving the pairing flow.
@MainActor
final class PairingViewModel: ObservableObject {

    @Published var state: PairingState = .idle

    /// Text for the share sheet.
    var shareText: String? {
        guard case .complete(let report) = state else { return nil }
        return """
        EdgeML Benchmark Results
        Model: \(report.modelName)
        Device: \(report.deviceName) (\(report.chipFamily))
        Tokens/sec: \(String(format: "%.1f", report.tokensPerSecond))
        TTFT: \(String(format: "%.1f", report.ttftMs)) ms
        TPOT: \(String(format: "%.1f", report.tpotMs)) ms
        p50: \(String(format: "%.1f", report.p50LatencyMs)) ms
        p95: \(String(format: "%.1f", report.p95LatencyMs)) ms
        Memory Peak: \(String(format: "%.1f", Double(report.memoryPeakBytes) / (1024 * 1024))) MB
        """
    }

    func reset() {
        state = .idle
    }

    func startPairing(code: String, serverURL: URL) {
        state = .connecting

        Task {
            do {
                let manager = PairingManager(serverURL: serverURL)

                // Step 1: Connect to session
                let session = try await manager.connect(code: code)
                state = .waiting(modelName: session.modelName)

                // Step 2: Wait for model deployment
                let deployment = try await manager.waitForDeployment(code: code)
                state = .downloading(progress: 0.5)

                // Step 3: Download model and run benchmarks
                state = .benchmarking(metrics: LiveMetrics())
                let report = try await manager.executeDeployment(deployment)

                // Step 4: Submit benchmark results
                try? await manager.submitBenchmark(code: code, report: report)

                state = .complete(report: report)
            } catch {
                state = .error(message: error.localizedDescription)
            }
        }
    }
}

// MARK: - Preview

struct PairingView_Previews: PreviewProvider {
    static var previews: some View {
        PairingView()
    }
}
#endif
