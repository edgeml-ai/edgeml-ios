import SwiftUI
import Octomil

/// Main application entry point for the Octomil pilot reference app.
///
/// Wires together:
/// - `AppState` as the shared environment object
/// - `MainTabView` with SDK Demo and Paired Model tabs
/// - `.octomilPairing()` modifier for automatic deep link handling
/// - `DiscoveryManager` for Bonjour advertising on the local network
///
/// The full `octomil deploy --phone` flow:
/// 1. App starts -> begins Bonjour discovery
/// 2. CLI finds device on local network
/// 3. CLI sends deep link (`octomil://pair?token=X&host=Y`)
/// 4. `.octomilPairing()` handles the link, presents `PairingScreen`
/// 5. On success, user taps "Try it out" -> switches to Paired Model tab
@main
struct OctomilDemoApp: App {
    @StateObject private var appState = AppState()

    init() {
        BackgroundSync.registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environmentObject(appState)
                .octomilPairing(
                    onTryModel: { modelInfo in
                        appState.pairedModel = modelInfo
                        appState.selectedTab = .paired
                    },
                    onOpenDashboard: {
                        #if canImport(UIKit)
                        if let url = URL(string: "https://app.octomil.com") {
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
