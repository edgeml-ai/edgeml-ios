import SwiftUI
import EdgeML

/// Main content view demonstrating EdgeML SDK usage
struct ContentView: View {

    @StateObject private var viewModel = EdgeMLDemoViewModel()

    var body: some View {
        NavigationStack {
            List {
                // Registration Section
                Section("Device Registration") {
                    registrationRow
                }

                // Model Section
                Section("Model Management") {
                    modelRow
                    if viewModel.model != nil {
                        modelInfoRow
                    }
                }

                // Inference Section
                if viewModel.model != nil {
                    Section("Inference") {
                        inferenceRow
                    }
                }

                // Training Section
                if viewModel.model?.supportsTraining == true {
                    Section("Training") {
                        trainingRow
                    }
                }

                // Status Section
                Section("Status") {
                    statusRow
                }
            }
            .navigationTitle("EdgeML Demo")
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) {
                    // No action needed — dismisses the alert via isPresented binding
                }
            } message: {
                Text(viewModel.errorMessage)
            }
        }
    }

    // MARK: - Row Views

    private var registrationRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Registration Status")
                    .font(.headline)
                Text(viewModel.isRegistered ? "Registered" : "Not Registered")
                    .font(.caption)
                    .foregroundColor(viewModel.isRegistered ? .green : .secondary)
                if let deviceId = viewModel.deviceId {
                    Text("Device: \(deviceId.prefix(12))...")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if !viewModel.isRegistered {
                Button("Register") {
                    Task {
                        await viewModel.registerDevice()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isLoading)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
    }

    private var modelRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Model")
                    .font(.headline)
                if let model = viewModel.model {
                    Text("\(model.id) v\(model.version)")
                        .font(.caption)
                        .foregroundColor(.green)
                } else {
                    Text("No model loaded")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if viewModel.isRegistered {
                Button(viewModel.model == nil ? "Download" : "Refresh") {
                    Task {
                        await viewModel.downloadModel()
                    }
                }
                .buttonStyle(.bordered)
                .disabled(viewModel.isLoading)
            }
        }
    }

    @ViewBuilder
    private var modelInfoRow: some View {
        if let model = viewModel.model {
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Model ID", value: model.id)
                InfoRow(label: "Version", value: model.version)
                InfoRow(label: "Supports Training", value: model.supportsTraining ? "Yes" : "No")
                InfoRow(label: "Inputs", value: "\(model.inputDescriptions.count) features")
                InfoRow(label: "Outputs", value: "\(model.outputDescriptions.count) outputs")
            }
            .font(.caption)
        }
    }

    private var inferenceRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Run Inference")
                    .font(.headline)
                if let result = viewModel.lastInferenceResult {
                    Text("Last result: \(result)")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            Spacer()

            Button("Predict") {
                Task {
                    await viewModel.runInference()
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(viewModel.isLoading)
        }
    }

    private var trainingRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("Local Training")
                    .font(.headline)
                if let result = viewModel.lastTrainingResult {
                    Text("Samples: \(result.sampleCount), Time: \(String(format: "%.2fs", result.trainingTime))")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }

            Spacer()

            Button("Train") {
                Task {
                    await viewModel.runTraining()
                }
            }
            .buttonStyle(.bordered)
            .disabled(viewModel.isLoading)
        }
    }

    private var statusRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Network")
                Spacer()
                Text(viewModel.isNetworkAvailable ? "Connected" : "Offline")
                    .foregroundColor(viewModel.isNetworkAvailable ? .green : .red)
            }

            HStack {
                Text("Background Training")
                Spacer()
                Toggle("", isOn: $viewModel.backgroundTrainingEnabled)
                    .onChange(of: viewModel.backgroundTrainingEnabled) { enabled in
                        viewModel.toggleBackgroundTraining(enabled: enabled)
                    }
            }

            if viewModel.isLoading {
                HStack {
                    Text("Loading...")
                    Spacer()
                    ProgressView()
                }
            }
        }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
        }
    }
}

// MARK: - Preview

#Preview {
    ContentView()
}
