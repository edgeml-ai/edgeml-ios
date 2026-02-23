#if os(iOS)
import SwiftUI
import Octomil

/// App Clip entry point for the Octomil pairing flow.
///
/// When building an App Clip target in Xcode, use this as the `@main` app type:
///
/// ```swift
/// // In your App Clip target's entry point:
/// @main
/// struct MyAppClip: App {
///     var body: some Scene {
///         WindowGroup {
///             OctomilClipRootView()
///         }
///     }
/// }
/// ```
///
/// Or use ``OctomilClipApp`` directly:
/// ```swift
/// // In your App Clip target:
/// @main typealias AppClip = OctomilClipApp
/// ```
public struct OctomilClipApp: App {
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
/// App Clip layout rather than using ``OctomilClipApp`` directly.
public struct OctomilClipRootView: View {
    public init() {}

    public var body: some View {
        PairingView()
    }
}
#endif
