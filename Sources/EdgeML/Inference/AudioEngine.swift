import Foundation

/// CoreML-based audio generation engine for iOS.
///
/// Audio frames are emitted as chunks, each containing a buffer of PCM samples.
public final class AudioEngine: StreamingInferenceEngine, @unchecked Sendable {

    /// Path to the CoreML audio model package.
    private let modelPath: URL

    /// Duration of audio to generate in seconds.
    public var durationSeconds: Double

    /// Sample rate in Hz.
    public var sampleRate: Int

    /// Creates an audio generation engine.
    /// - Parameters:
    ///   - modelPath: File URL pointing to the CoreML model package.
    ///   - durationSeconds: Target duration (default: 5.0).
    ///   - sampleRate: Audio sample rate (default: 16000).
    public init(modelPath: URL, durationSeconds: Double = 5.0, sampleRate: Int = 16000) {
        self.modelPath = modelPath
        self.durationSeconds = durationSeconds
        self.sampleRate = sampleRate
    }

    // MARK: - StreamingInferenceEngine

    public func generate(input _: Any, modality _: Modality) -> AsyncThrowingStream<InferenceChunk, Error> {
        let sampleRate = self.sampleRate
        let totalFrames = Int(durationSeconds * Double(sampleRate) / 1024)

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for frame in 0..<totalFrames {
                        if Task.isCancelled { break }

                        // Placeholder audio frame (1024 samples × 2 bytes each)
                        let frameData = Data(repeating: 0, count: 1024 * 2)
                        let chunk = InferenceChunk(
                            index: frame,
                            data: frameData,
                            modality: .audio,
                            timestamp: Date(),
                            latencyMs: 0
                        )
                        continuation.yield(chunk)

                        try await Task.sleep(nanoseconds: 10_000_000) // 10ms
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
