import Foundation
import Octomil
#if canImport(UIKit)
import UIKit
#endif

/// Shared application state for the Octomil pilot reference app.
///
/// Manages tab selection, paired model state, and local network discovery.
/// Injected into the view hierarchy as an `@EnvironmentObject`.
@MainActor
class AppState: ObservableObject {

    // MARK: - Published State

    @Published var selectedTab: AppTab = .demo
    @Published var pairedModel: PairedModelInfo?

    // MARK: - Discovery

    private let discoveryManager = DiscoveryManager()

    /// Begin advertising this device on the local network via Bonjour.
    ///
    /// The Octomil CLI (`octomil deploy --phone`) discovers devices through
    /// mDNS, so this must be running for the deploy flow to work.
    func startDiscovery() {
        let deviceId: String
        #if canImport(UIKit)
        deviceId = UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
        #else
        deviceId = UUID().uuidString
        #endif

        let deviceName: String
        #if canImport(UIKit)
        deviceName = UIDevice.current.name
        #else
        deviceName = Host.current().localizedName ?? "Mac"
        #endif

        discoveryManager.startDiscoverable(
            deviceId: deviceId,
            deviceName: deviceName
        )
    }

    /// Stop advertising on the local network.
    func stopDiscovery() {
        discoveryManager.stopDiscoverable()
    }
}

// MARK: - Tab Enum

/// Tabs available in the main `TabView`.
enum AppTab: Hashable {
    /// The SDK demo tab (registration, model management, inference, training).
    case demo
    /// The paired model tab (shows `TryItOutScreen` after `octomil deploy --phone`).
    case paired
}
