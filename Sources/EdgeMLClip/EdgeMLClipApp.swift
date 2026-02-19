#if os(iOS)
import SwiftUI
import EdgeML

/// App Clip entry point for the EdgeML pairing flow.
///
/// When building an App Clip target in Xcode, use this as the `@main` app type:
///
/// ```swift
/// // In your App Clip target's entry point:
/// @main
/// struct MyAppClip: App {
///     var body: some Scene {
///         WindowGroup {
///             EdgeMLClipRootView()
///         }
///     }
/// }
/// ```
///
/// Or use ``EdgeMLClipApp`` directly:
/// ```swift
/// // In your App Clip target:
/// @main typealias AppClip = EdgeMLClipApp
/// ```
public struct EdgeMLClipApp: App {
    public init() {}

    public var body: some Scene {
        WindowGroup {
            PairingView()
        }
    }
}

/// Root view for embedding the pairing flow in an App Clip.
///
/// Use this if you want to embed the pairing view inside a custom
/// App Clip layout rather than using ``EdgeMLClipApp`` directly.
public struct EdgeMLClipRootView: View {
    public init() {}

    public var body: some View {
        PairingView()
    }
}
#endif
