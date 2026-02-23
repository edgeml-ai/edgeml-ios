#if canImport(SwiftUI)
import SwiftUI
#if canImport(AVFoundation)
import AVFoundation
#endif

/// Audio input UI with a record button and transcription output.
///
/// On iOS, wraps ``AVAudioRecorder`` for microphone input. The user taps
/// to start and stop recording, then the audio data is sent to the model
/// for transcription.
@available(iOS 15.0, macOS 12.0, *)
struct AudioInputView: View {

    @ObservedObject var viewModel: TryItOutViewModel
    @StateObject private var recorder = AudioRecorderState()

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            // Output area
            outputArea
                .padding(.horizontal, 16)

            Spacer()

            // Record button
            recordSection
                .padding(.bottom, 40)
        }
    }

    // MARK: - Output Area

    @ViewBuilder
    private var outputArea: some View {
        switch viewModel.inferenceState {
        case .idle:
            idleState

        case .loading:
            VStack(spacing: 12) {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .scaleEffect(1.2)

                Text("Transcribing...")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.6))
            }

        case .result(let output, let latencyMs):
            VStack(spacing: 12) {
                HStack {
                    Text("Transcription")
                        .font(.caption)
                        .foregroundColor(.white.opacity(0.5))
                    Spacer()
                    LatencyBadge(latencyMs: latencyMs)
                }

                Text(output)
                    .font(.body)
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.white.opacity(0.06))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.white.opacity(0.1), lineWidth: 1)
                    )
            }

        case .error(let message):
            VStack(alignment: .leading, spacing: 6) {
                Text("Error")
                    .font(.caption)
                    .foregroundColor(.orange)

                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.orange.opacity(0.8))
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.orange.opacity(0.1))
                    )
            }
        }
    }

    private var idleState: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform")
                .font(.system(size: 40))
                .foregroundColor(.white.opacity(0.2))

            Text("Tap the microphone to record")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.4))
        }
    }

    // MARK: - Record Section

    private var recordSection: some View {
        VStack(spacing: 12) {
            // Recording duration
            if recorder.isRecording {
                Text(recorder.formattedDuration)
                    .font(.system(.title3, design: .monospaced))
                    .foregroundColor(.red)
            }

            // Record button
            Button {
                toggleRecording()
            } label: {
                ZStack {
                    Circle()
                        .fill(recorder.isRecording
                              ? Color.red.opacity(0.2)
                              : Color.white.opacity(0.08))
                        .frame(width: 80, height: 80)

                    Circle()
                        .stroke(recorder.isRecording
                                ? Color.red
                                : Color.white.opacity(0.3),
                                lineWidth: 3)
                        .frame(width: 80, height: 80)

                    if recorder.isRecording {
                        RoundedRectangle(cornerRadius: 4)
                            .fill(Color.red)
                            .frame(width: 24, height: 24)
                    } else {
                        Image(systemName: "mic.fill")
                            .font(.system(size: 28))
                            .foregroundColor(.white.opacity(0.8))
                    }
                }
            }

            Text(recorder.isRecording ? "Tap to stop" : "Tap to record")
                .font(.caption)
                .foregroundColor(.white.opacity(0.4))
        }
    }

    // MARK: - Actions

    private func toggleRecording() {
        if recorder.isRecording {
            if let data = recorder.stopRecording() {
                viewModel.transcribeAudio(audioData: data)
            }
        } else {
            recorder.startRecording()
        }
    }
}

// MARK: - Audio Recorder State

/// Observable wrapper around AVAudioRecorder for the audio input view.
///
/// On platforms without AVAudioRecorder (macOS sandbox, simulator), this
/// gracefully degrades -- `startRecording()` becomes a no-op and
/// `stopRecording()` returns placeholder data.
@available(iOS 15.0, macOS 12.0, *)
final class AudioRecorderState: ObservableObject {
    @Published var isRecording = false
    @Published var recordingDuration: TimeInterval = 0

    #if canImport(AVFoundation) && canImport(UIKit)
    private var audioRecorder: AVAudioRecorder?
    #endif
    private var timer: Timer?
    private var recordingURL: URL?

    var formattedDuration: String {
        let minutes = Int(recordingDuration) / 60
        let seconds = Int(recordingDuration) % 60
        return String(format: "%d:%02d", minutes, seconds)
    }

    func startRecording() {
        isRecording = true
        recordingDuration = 0

        let tempDir = FileManager.default.temporaryDirectory
        let fileURL = tempDir.appendingPathComponent("octomil_recording_\(UUID().uuidString).m4a")
        recordingURL = fileURL

        #if canImport(AVFoundation) && canImport(UIKit)
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
        ]

        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default)
            try session.setActive(true)

            audioRecorder = try AVAudioRecorder(url: fileURL, settings: settings)
            audioRecorder?.record()
        } catch {
            // Recording failed -- will return placeholder on stop
        }
        #endif

        // Update duration timer
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.recordingDuration += 0.1
        }
    }

    func stopRecording() -> Data? {
        isRecording = false
        timer?.invalidate()
        timer = nil

        #if canImport(AVFoundation) && canImport(UIKit)
        audioRecorder?.stop()
        audioRecorder = nil
        #endif

        guard let url = recordingURL else {
            // Return placeholder data for platforms without AVFoundation
            return Data([0x00])
        }

        defer {
            try? FileManager.default.removeItem(at: url)
            recordingURL = nil
        }

        return try? Data(contentsOf: url)
    }
}
#endif
