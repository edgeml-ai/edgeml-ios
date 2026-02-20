#if canImport(SwiftUI)
import SwiftUI

/// View modifier that presents ``PairingScreen`` automatically when an
/// `edgeml://pair?token=X&host=Y` deep link is received.
///
/// # Usage
///
/// ```swift
/// @main
/// struct MyApp: App {
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///                 .edgeMLPairing()
///         }
///     }
/// }
/// ```
///
/// The modifier listens for `onOpenURL` events. When a URL matching the
/// `edgeml://pair` scheme/host is received, it extracts the `token` and
/// `host` parameters and presents a full-screen ``PairingScreen``.
@available(iOS 15.0, macOS 12.0, *)
struct EdgeMLPairingModifier: ViewModifier {

    @State private var pairingToken: String?
    @State private var pairingHost: String?
    @State private var isPairing = false

    /// Optional callback when the user taps "Try it out".
    var onTryModel: ((PairedModelInfo) -> Void)?

    /// Optional callback when the user taps "Open Dashboard".
    var onOpenDashboard: (() -> Void)?

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in
                handleURL(url)
            }
            .fullScreenCover(isPresented: $isPairing) {
                if let token = pairingToken, let host = pairingHost {
                    PairingScreen(
                        token: token,
                        host: host,
                        onTryModel: { model in
                            isPairing = false
                            onTryModel?(model)
                        },
                        onOpenDashboard: {
                            isPairing = false
                            onOpenDashboard?()
                        }
                    )
                    #if os(iOS)
                    .statusBarHidden(false)
                    #endif
                }
            }
    }

    private func handleURL(_ url: URL) {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return
        }

        // Support both edgeml://pair?token=X&host=Y
        // and https://app.edgeml.io/pair?token=X&host=Y
        let isPairAction: Bool
        if components.scheme == "edgeml" && components.host == "pair" {
            isPairAction = true
        } else if components.path.hasSuffix("/pair") {
            isPairAction = true
        } else {
            isPairAction = false
        }

        guard isPairAction else { return }

        let queryItems = components.queryItems ?? []
        guard let token = queryItems.first(where: { $0.name == "token" })?.value,
              !token.isEmpty else {
            return
        }

        let host = queryItems.first(where: { $0.name == "host" })?.value ?? "https://api.edgeml.io"

        pairingToken = token
        pairingHost = host
        isPairing = true
    }
}

// MARK: - View Extension

@available(iOS 15.0, macOS 12.0, *)
public extension View {

    /// Adds automatic EdgeML pairing support to this view.
    ///
    /// When the app receives a deep link matching `edgeml://pair?token=X&host=Y`,
    /// a full-screen pairing flow is presented automatically.
    ///
    /// ```swift
    /// ContentView()
    ///     .edgeMLPairing()
    /// ```
    ///
    /// - Parameters:
    ///   - onTryModel: Called when the user taps "Try it out" after successful pairing.
    ///   - onOpenDashboard: Called when the user taps "Open Dashboard".
    /// - Returns: A view with EdgeML pairing deep link handling.
    func edgeMLPairing(
        onTryModel: ((PairedModelInfo) -> Void)? = nil,
        onOpenDashboard: (() -> Void)? = nil
    ) -> some View {
        modifier(
            EdgeMLPairingModifier(
                onTryModel: onTryModel,
                onOpenDashboard: onOpenDashboard
            )
        )
    }
}
#endif
