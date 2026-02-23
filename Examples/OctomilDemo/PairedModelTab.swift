import SwiftUI
import Octomil

/// Tab content for the "Paired Model" tab.
///
/// When a model has been paired via `octomil deploy --phone`, displays the
/// SDK-provided `TryItOutScreen` which auto-selects the right modality UI
/// (text, vision, audio, classification).
///
/// When no model is paired, shows a waiting state with discovery status
/// and instructions.
struct PairedModelTab: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        if let model = appState.pairedModel {
            TryItOutScreen(modelInfo: model)
        } else {
            waitingState
        }
    }

    // MARK: - Waiting State

    private var waitingState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 60))
                .foregroundColor(.secondary)

            Text("No Model Paired")
                .font(.title2)
                .fontWeight(.semibold)

            Text("Run `octomil deploy <model> --phone` from your terminal to deploy a model to this device.")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)

            // Discovery status indicator
            HStack {
                Circle()
                    .fill(.green)
                    .frame(width: 8, height: 8)
                Text("Discoverable on local network")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding()
    }
}
