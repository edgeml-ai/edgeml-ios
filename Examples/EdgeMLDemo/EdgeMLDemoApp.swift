import SwiftUI
import EdgeML
import CoreML

/// Main application entry point for EdgeML Demo
@main
struct EdgeMLDemoApp: App {

    init() {
        // Register background tasks on app launch
        BackgroundSync.registerBackgroundTasks()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
