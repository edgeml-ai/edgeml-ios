import Foundation

// MARK: - Deep Link Action

/// Actions that can be triggered by an `edgeml://` deep link.
///
/// The EdgeML SDK defines a custom URL scheme (`edgeml://`) for deep linking
/// into the app. This enum represents the supported actions that can be parsed
/// from an incoming URL.
///
/// ## Supported URL Formats
///
/// **Pairing:**
/// ```
/// edgeml://pair?token=<pairing-token>&host=<server-host>
/// ```
///
/// - `token` (required): The pairing token from the QR code or CLI.
/// - `host` (optional): The server host to connect to. If omitted,
///   the consuming app should use its configured default server URL.
///
/// ## App Integration
///
/// Since EdgeML is an SPM library (not an app), the consuming app must register
/// the `edgeml` URL scheme in its `Info.plist`:
///
/// ```xml
/// <key>CFBundleURLTypes</key>
/// <array>
///   <dict>
///     <key>CFBundleURLSchemes</key>
///     <array>
///       <string>edgeml</string>
///     </array>
///     <key>CFBundleURLName</key>
///     <string>ai.edgeml.deeplink</string>
///   </dict>
/// </array>
/// ```
///
/// Then handle the URL in your SwiftUI app:
///
/// ```swift
/// @main
/// struct MyApp: App {
///     var body: some Scene {
///         WindowGroup {
///             ContentView()
///                 .onOpenURL { url in
///                     if let action = DeepLinkHandler.parse(url: url) {
///                         handleDeepLink(action)
///                     }
///                 }
///         }
///     }
/// }
/// ```
///
/// Or in a UIKit `AppDelegate`:
///
/// ```swift
/// func application(
///     _ app: UIApplication,
///     open url: URL,
///     options: [UIApplication.OpenURLOptionsKey: Any] = [:]
/// ) -> Bool {
///     guard let action = DeepLinkHandler.parse(url: url) else {
///         return false
///     }
///     handleDeepLink(action)
///     return true
/// }
/// ```
public enum DeepLinkAction: Sendable, Equatable {
    /// Pair this device with the EdgeML server using a token from `edgeml deploy --phone`.
    ///
    /// - Parameters:
    ///   - token: The pairing token (maps to the pairing code used by ``PairingManager``).
    ///   - host: Optional server host override (e.g. `"https://api.edgeml.io"`).
    ///           When `nil`, the consuming app should use its configured default.
    case pair(token: String, host: String?)

    /// The URL matched the `edgeml://` scheme but the action is not recognized.
    ///
    /// The consuming app may choose to log this or display an error.
    case unknown(url: URL)
}

// MARK: - Deep Link Handler

/// Parses `edgeml://` URLs into structured ``DeepLinkAction`` values.
///
/// `DeepLinkHandler` is the SDK's entry point for handling deep links. It is
/// a pure, stateless parser with no side effects -- the consuming app decides
/// what to do with the parsed action.
///
/// ## Example
///
/// ```swift
/// let url = URL(string: "edgeml://pair?token=abc123&host=https://api.edgeml.io")!
/// if let action = DeepLinkHandler.parse(url: url) {
///     switch action {
///     case .pair(let token, let host):
///         let serverURL = host.flatMap(URL.init(string:))
///             ?? URL(string: "https://api.edgeml.io")!
///         let manager = PairingManager(serverURL: serverURL)
///         let report = try await manager.pair(code: token)
///
///     case .unknown(let url):
///         print("Unrecognized deep link: \(url)")
///     }
/// }
/// ```
public struct DeepLinkHandler: Sendable {

    /// The URL scheme handled by the EdgeML SDK.
    public static let scheme = "edgeml"

    /// Parses an incoming URL into a ``DeepLinkAction``.
    ///
    /// Returns `nil` if the URL does not use the `edgeml` scheme.
    ///
    /// - Parameter url: The incoming URL to parse.
    /// - Returns: A ``DeepLinkAction`` if the URL uses the `edgeml` scheme, or `nil`.
    public static func parse(url: URL) -> DeepLinkAction? {
        guard url.scheme == scheme else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)

        switch url.host {
        case "pair":
            let queryItems = components?.queryItems ?? []
            let token = queryItems.first(where: { $0.name == "token" })?.value
            let host = queryItems.first(where: { $0.name == "host" })?.value

            guard let token, !token.isEmpty else { return nil }
            return .pair(token: token, host: host)

        default:
            return .unknown(url: url)
        }
    }

    // Private init -- this type is a namespace for static methods.
    private init() {}
}
