import SwiftUI
import EdgeML

/// Main application entry point for the EdgeML pilot reference app.
///
/// Wires together:
/// - `AppState` as the shared environment object
/// - `MainTabView` with SDK Demo and Paired Model tabs
/// - `.edgeMLPairing()` modifier for automatic deep link handling
/// - `DiscoveryManager` for Bonjour advertising on the local network
///
/// The full `edgeml deploy --phone` flow:
/// 1. App starts -> begins Bonjour discovery
/// 2. CLI finds device on local network
/// 3. CLI sends deep link (`edgeml://pair?token=X&host=Y`)
/// 4. `.edgeMLPairing()` handles the link, presents `PairingScreen`
/// 5. On success, user taps "Try it out" -> switches to Paired Model tab
@main
struct EdgeMLDemoApp: App {
    @StateObject private var appState = AppState()

    init() {
        BackgroundSync.registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(appState)
                .edgeMLPairing(
                    onTryModel: { modelInfo in
                        appState.pairedModel = modelInfo
                        appState.selectedTab = .paired
                    },
                    onOpenDashboard: {
                        #if canImport(UIKit)
                        if let url = URL(string: "https://app.edgeml.io") {
                            UIApplication.shared.open(url)
                        }
                        #endif
                    }
                )
                .onAppear {
                    appState.startDiscovery()
                }
        }
    }
}
