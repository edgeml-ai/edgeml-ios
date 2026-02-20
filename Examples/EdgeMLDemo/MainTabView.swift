import SwiftUI
import EdgeML

/// Root tab view for the pilot reference app.
///
/// Two tabs:
/// - **SDK Demo**: The existing `ContentView` showcasing registration,
///   model download, inference, and training.
/// - **Paired Model**: Shows `TryItOutScreen` when a model has been
///   deployed via `edgeml deploy --phone`, otherwise a waiting placeholder.
struct MainTabView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView(selection: $appState.selectedTab) {
            ContentView()
                .tabItem {
                    Label("SDK Demo", systemImage: "wrench.and.screwdriver")
                }
                .tag(AppTab.demo)

            PairedModelTab()
                .tabItem {
                    Label("Paired Model", systemImage: "antenna.radiowaves.left.and.right")
                }
                .tag(AppTab.paired)
        }
    }
}
