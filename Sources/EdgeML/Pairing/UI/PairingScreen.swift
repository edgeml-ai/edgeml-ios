#if canImport(SwiftUI)
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A SwiftUI pairing screen for the main app target.
///
/// Present this view when a deep link (`edgeml://pair?token=X&host=Y`) is
/// received. It drives the full pairing flow through ``PairingViewModel``,
/// showing connecting, downloading, success, and error states.
///
/// # Usage
///
/// ```swift
/// PairingScreen(token: "ABC123", host: "https://api.edgeml.io")
/// ```
///
/// Or use the `.edgeMLPairing()` view modifier for automatic deep link handling.
@available(iOS 15.0, macOS 12.0, *)
public struct PairingScreen: View {

    @StateObject private var viewModel: PairingViewModel

    /// Callback invoked when the user taps "Try it out" on the success screen.
    /// When nil, the built-in ``TryItOutScreen`` is presented automatically.
    private let onTryModel: ((PairedModelInfo) -> Void)?

    /// Callback invoked when the user taps "Open Dashboard".
    private let onOpenDashboard: (() -> Void)?

    /// Tracks whether the built-in TryItOutScreen is being presented.
    @State private var showTryItOut = false
    @State private var tryItOutModelInfo: PairedModelInfo?


    /// Creates a pairing screen.
    /// - Parameters:
    ///   - token: Pairing code from the deep link.
    ///   - host: Server URL from the deep link.
    ///   - onTryModel: Called when the user taps "Try it out". When nil,
    ///     the built-in ``TryItOutScreen`` is presented automatically.
    ///   - onOpenDashboard: Called when the user taps "Open Dashboard".
    public init(
        token: String,
        host: String,
        onTryModel: ((PairedModelInfo) -> Void)? = nil,
        onOpenDashboard: (() -> Void)? = nil
    ) {
        _viewModel = StateObject(wrappedValue: PairingViewModel(token: token, host: host))
        self.onTryModel = onTryModel
        self.onOpenDashboard = onOpenDashboard
    }

    public var body: some View {
        ZStack {
            backgroundGradient
                .ignoresSafeArea()

            VStack(spacing: 0) {
                headerBar
                    .padding(.bottom, 8)

                Spacer()

                switch viewModel.state {
                case .connecting(let host):
                    connectingCard(host: host)

                case .downloading(let progress):
                    downloadingCard(progress: progress)

                case .success(let model):
                    successCard(model: model)

                case .error(let message):
                    errorCard(message: message)
                }

                Spacer()
            }
            .padding(.horizontal, 24)
        }
        .onAppear {
            viewModel.startPairing()
        }
        #if os(iOS)
        .fullScreenCover(isPresented: $showTryItOut) {
            if let info = tryItOutModelInfo {
                NavigationView {
                    TryItOutScreen(modelInfo: info)
                }
            }
        }
        #else
        .sheet(isPresented: $showTryItOut) {
            if let info = tryItOutModelInfo {
                NavigationView {
                    TryItOutScreen(modelInfo: info)
                        .frame(minWidth: 400, minHeight: 500)
                }
            }
        }
        #endif
    }

    // MARK: - Background

    private var backgroundGradient: some View {
        LinearGradient(
            colors: [
                Color(red: 0.05, green: 0.05, blue: 0.12),
                Color(red: 0.08, green: 0.08, blue: 0.18)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Circle()
                .fill(Color.green.opacity(0.8))
                .frame(width: 8, height: 8)
            Text("EdgeML")
                .font(.headline)
                .foregroundColor(.white.opacity(0.9))
            Spacer()
        }
        .padding(.top, 16)
    }

    // MARK: - Connecting State

    private func connectingCard(host: String) -> some View {
        PairingCardView {
            VStack(spacing: 20) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.3)

                Text("Connecting...")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                VStack(spacing: 6) {
                    Text("Server")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                    Text(displayHost(host))
                        .font(.system(.subheadline, design: .monospaced))
                        .foregroundColor(.white.opacity(0.8))
                }
            }
        }
    }

    // MARK: - Downloading State

    private func downloadingCard(progress: DownloadProgressInfo) -> some View {
        PairingCardView {
            VStack(spacing: 20) {
                Text("Downloading...")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text(progress.modelName)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.7))

                VStack(spacing: 8) {
                    GeometryReader { geo in
                        ZStack(alignment: .leading) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.white.opacity(0.15))
                                .frame(height: 8)

                            RoundedRectangle(cornerRadius: 4)
                                .fill(
                                    LinearGradient(
                                        colors: [Color.blue, Color.cyan],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .frame(width: max(0, geo.size.width * progress.fraction), height: 8)
                        }
                    }
                    .frame(height: 8)

                    HStack {
                        Text("\(Int(progress.fraction * 100))%")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundColor(.white.opacity(0.6))
                        Spacer()
                        if progress.totalBytes > 0 {
                            Text("\(progress.downloadedString) / \(progress.totalString)")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.white.opacity(0.6))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Success State

    private func successCard(model: PairedModelInfo) -> some View {
        PairingCardView {
            VStack(spacing: 20) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.green)

                Text("Ready!")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                VStack(spacing: 10) {
                    modelInfoRow(label: "Model", value: model.name)
                    modelInfoRow(label: "Version", value: model.version)
                    modelInfoRow(label: "Size", value: model.sizeString)
                    modelInfoRow(label: "Runtime", value: model.runtime)
                    if let tps = model.tokensPerSecond, tps > 0 {
                        modelInfoRow(label: "Perf", value: String(format: "%.1f tok/s", tps))
                    }
                }
                .padding(.vertical, 4)

                VStack(spacing: 10) {
                    Button {
                        if let handler = onTryModel {
                            handler(model)
                        } else {
                            tryItOutModelInfo = model
                            showTryItOut = true
                        }
                    } label: {
                        Text("Try it out")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(
                                LinearGradient(
                                    colors: [Color.blue, Color.cyan],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .cornerRadius(10)
                    }

                    Button {
                        if let handler = onOpenDashboard {
                            handler()
                        } else {
                            openDashboardFallback()
                        }
                    } label: {
                        Text("Open Dashboard")
                            .font(.subheadline)
                            .fontWeight(.medium)
                            .foregroundColor(.white.opacity(0.7))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(Color.white.opacity(0.1))
                            .cornerRadius(10)
                    }
                }
            }
        }
    }

    // MARK: - Error State

    private func errorCard(message: String) -> some View {
        PairingCardView {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.orange)

                Text("Pairing Failed")
                    .font(.title3)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    viewModel.retry()
                } label: {
                    Text("Retry")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.orange.opacity(0.8))
                        .cornerRadius(10)
                }
            }
        }
    }

    // MARK: - Helpers

    private func modelInfoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.5))
            Spacer()
            Text(value)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(.white.opacity(0.9))
        }
    }

    private func displayHost(_ host: String) -> String {
        // Strip scheme for display
        var display = host
        if display.hasPrefix("https://") {
            display = String(display.dropFirst(8))
        } else if display.hasPrefix("http://") {
            display = String(display.dropFirst(7))
        }
        // Strip trailing slash
        if display.hasSuffix("/") {
            display = String(display.dropLast())
        }
        return display
    }

    private func openDashboardFallback() {
        #if canImport(UIKit)
        if let url = URL(string: "https://app.edgeml.io") {
            UIApplication.shared.open(url)
        }
        #endif
    }
}

// MARK: - Card Container

/// Rounded card with translucent background used by ``PairingScreen``.
@available(iOS 15.0, macOS 12.0, *)
struct PairingCardView<Content: View>: View {
    let content: () -> Content

    init(@ViewBuilder content: @escaping () -> Content) {
        self.content = content
    }

    var body: some View {
        content()
            .padding(24)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.white.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
    }
}

// MARK: - Preview

#if DEBUG
@available(iOS 15.0, macOS 12.0, *)
struct PairingScreen_Previews: PreviewProvider {
    static var previews: some View {
        PairingScreen(
            token: "ABC123",
            host: "https://api.edgeml.io"
        )
    }
}
#endif
#endif
