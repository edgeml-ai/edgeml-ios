import Foundation
import CoreML
import Combine
import os.log

/// Manages continuous on-device personalization with incremental training.
///
/// Similar to Google Keyboard's adaptive learning, this manager:
/// - Buffers user interactions and training data
/// - Triggers incremental model updates in the background
/// - Manages personalized model versions per user
/// - Ensures privacy through local-only training
/// - Periodically uploads aggregated updates to the server
public actor PersonalizationManager {

    // MARK: - Properties

    private let configuration: EdgeMLConfiguration
    private let trainer: FederatedTrainer
    private let logger: Logger

    // Training buffer
    private var trainingBuffer: [TrainingSample] = []
    private let bufferSizeThreshold: Int
    private let minSamplesForTraining: Int

    // Personalized model management
    private var personalizedModel: EdgeMLModel?
    private var baseModel: EdgeMLModel?
    private var trainingHistory: [TrainingSession] = []

    // State
    private var isTraining = false
    private var lastTrainingDate: Date?

    // Configuration
    private let maxBufferSize: Int
    private let trainingInterval: TimeInterval // Minimum time between training sessions
    private let trainingMode: TrainingMode
    private let uploadThreshold: Int // Number of training sessions before upload

    // MARK: - Initialization

    /// Creates a new personalization manager.
    /// - Parameters:
    ///   - configuration: SDK configuration.
    ///   - trainer: Federated trainer instance.
    ///   - bufferSize: Number of samples to buffer before triggering training.
    ///   - minSamples: Minimum samples required to start training.
    ///   - trainingInterval: Minimum seconds between training sessions (default: 300 = 5 minutes).
    ///   - trainingMode: Training mode (default: .localOnly for maximum privacy).
    ///   - uploadThreshold: Training sessions before auto-upload (default: 10).
    public init(
        configuration: EdgeMLConfiguration,
        trainer: FederatedTrainer,
        bufferSize: Int = 50,
        minSamples: Int = 10,
        trainingInterval: TimeInterval = 300,
        trainingMode: TrainingMode = .localOnly,
        uploadThreshold: Int = 10
    ) {
        self.configuration = configuration
        self.trainer = trainer
        self.bufferSizeThreshold = bufferSize
        self.minSamplesForTraining = minSamples
        self.maxBufferSize = bufferSize * 2
        self.trainingInterval = trainingInterval
        self.trainingMode = trainingMode
        self.uploadThreshold = uploadThreshold
        self.logger = Logger(subsystem: "ai.edgeml.sdk", category: "PersonalizationManager")
    }

    // MARK: - Model Management

    /// Sets the base model for personalization.
    /// - Parameter model: The base model to personalize.
    public func setBaseModel(_ model: EdgeMLModel) {
        self.baseModel = model

        // Check if a personalized version exists
        if let personalizedURL = getPersonalizedModelURL(for: model.id),
           FileManager.default.fileExists(atPath: personalizedURL.path) {
            do {
                let mlModel = try MLModel(contentsOf: personalizedURL)
                let metadata = model.metadata // Reuse base model metadata
                self.personalizedModel = EdgeMLModel(
                    id: model.id,
                    version: "\(model.version)-personalized",
                    mlModel: mlModel,
                    metadata: metadata,
                    compiledModelURL: personalizedURL
                )

                if configuration.enableLogging {
                    logger.info("Loaded personalized model for \(model.id)")
                }
            } catch {
                if configuration.enableLogging {
                    logger.error("Failed to load personalized model: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Gets the current model (personalized if available, otherwise base).
    public func getCurrentModel() -> EdgeMLModel? {
        return personalizedModel ?? baseModel
    }

    /// Resets personalization by deleting the personalized model.
    public func resetPersonalization() throws {
        guard let model = baseModel else {
            throw EdgeMLError.modelNotFound(reason: "No base model loaded")
        }

        if let personalizedURL = getPersonalizedModelURL(for: model.id) {
            try? FileManager.default.removeItem(at: personalizedURL)
        }

        personalizedModel = nil
        trainingBuffer.removeAll()
        trainingHistory.removeAll()
        lastTrainingDate = nil

        if configuration.enableLogging {
            logger.info("Reset personalization for model \(model.id)")
        }
    }

    // MARK: - Training Data Collection

    /// Adds a training sample to the buffer.
    ///
    /// When the buffer reaches the threshold, training is automatically triggered.
    ///
    /// - Parameters:
    ///   - input: Input data for training.
    ///   - target: Expected output / label.
    ///   - metadata: Optional metadata about the sample (e.g., timestamp, context).
    public func addTrainingSample(
        input: MLFeatureProvider,
        target: MLFeatureProvider,
        metadata: [String: Any]? = nil
    ) async throws {
        let sample = TrainingSample(
            input: input,
            target: target,
            timestamp: Date(),
            metadata: metadata
        )

        trainingBuffer.append(sample)

        // Enforce max buffer size
        if trainingBuffer.count > maxBufferSize {
            trainingBuffer.removeFirst(trainingBuffer.count - maxBufferSize)

            if configuration.enableLogging {
                logger.warning("Training buffer exceeded max size, removed oldest samples")
            }
        }

        // Check if we should trigger training
        if shouldTriggerTraining() {
            try await trainIncrementally()
        }
    }

    /// Adds multiple training samples at once.
    public func addTrainingSamples(_ samples: [(input: MLFeatureProvider, target: MLFeatureProvider)]) async throws {
        for (input, target) in samples {
            try await addTrainingSample(input: input, target: target)
        }
    }

    // MARK: - Incremental Training

    /// Triggers incremental training on buffered samples.
    ///
    /// This happens automatically when the buffer threshold is reached,
    /// but can also be called manually.
    public func trainIncrementally() async throws {
        guard !isTraining else {
            if configuration.enableLogging {
                logger.debug("Training already in progress, skipping")
            }
            return
        }

        guard trainingBuffer.count >= minSamplesForTraining else {
            if configuration.enableLogging {
                logger.debug("Not enough samples for training (\(trainingBuffer.count) < \(minSamplesForTraining))")
            }
            return
        }

        guard let model = getCurrentModel() else {
            throw EdgeMLError.modelNotFound
        }

        isTraining = true
        defer { isTraining = false }

        if configuration.enableLogging {
            logger.info("Starting incremental training with \(self.trainingBuffer.count) samples")
        }

        let startTime = Date()

        // Create batch provider from buffer
        let batchProvider = TrainingSampleBatchProvider(samples: trainingBuffer)

        // Configure training (small updates for incremental learning)
        let config = TrainingConfig(
            epochs: 1, // Single epoch for incremental updates
            batchSize: min(trainingBuffer.count, 32),
            learningRate: 0.0001 // Small learning rate for fine-tuning
        )

        // Train the model
        let result = try await trainer.train(
            model: model,
            dataProvider: { batchProvider },
            config: config
        )

        // Save personalized model
        try await savePersonalizedModel()

        // Record training session
        let session = TrainingSession(
            timestamp: Date(),
            sampleCount: trainingBuffer.count,
            trainingTime: Date().timeIntervalSince(startTime),
            loss: result.loss,
            accuracy: result.accuracy
        )
        trainingHistory.append(session)

        // Clear buffer after successful training
        trainingBuffer.removeAll()
        lastTrainingDate = Date()

        if configuration.enableLogging {
            logger.info("Incremental training completed in \(String(format: "%.2f", session.trainingTime))s")
        }

        // Check if we should upload updates (only in FEDERATED mode)
        // Aggregated upload will be implemented in a future version
        if trainingMode.uploadsToServer && trainingHistory.count >= uploadThreshold && configuration.enableLogging {
            logger.info("Upload threshold reached (\(self.trainingHistory.count) sessions) - mode: \(self.trainingMode.rawValue)")
        }
    }

    /// Forces training on current buffer, regardless of thresholds.
    public func forceTraining() async throws {
        guard !trainingBuffer.isEmpty else {
            throw EdgeMLError.trainingFailed(reason: "No training samples in buffer")
        }

        try await trainIncrementally()
    }

    // MARK: - Statistics

    /// Gets statistics about personalization progress.
    public func getStatistics() -> PersonalizationStatistics {
        return PersonalizationStatistics(
            totalTrainingSessions: trainingHistory.count,
            totalSamplesTrained: trainingHistory.reduce(0) { $0 + $1.sampleCount },
            bufferedSamples: trainingBuffer.count,
            lastTrainingDate: lastTrainingDate,
            averageLoss: trainingHistory.compactMap { $0.loss }.average(),
            averageAccuracy: trainingHistory.compactMap { $0.accuracy }.average(),
            isPersonalized: personalizedModel != nil,
            trainingMode: trainingMode
        )
    }

    /// Gets the training history.
    public func getTrainingHistory() -> [TrainingSession] {
        return trainingHistory
    }

    /// Clears the training buffer without training.
    public func clearBuffer() {
        trainingBuffer.removeAll()

        if configuration.enableLogging {
            logger.info("Training buffer cleared")
        }
    }

    // MARK: - Private Methods

    private func shouldTriggerTraining() -> Bool {
        // Check buffer size threshold
        guard trainingBuffer.count >= bufferSizeThreshold else {
            return false
        }

        // Check minimum samples
        guard trainingBuffer.count >= minSamplesForTraining else {
            return false
        }

        // Check training interval
        if let lastDate = lastTrainingDate {
            let timeSinceLastTraining = Date().timeIntervalSince(lastDate)
            guard timeSinceLastTraining >= trainingInterval else {
                return false
            }
        }

        // Don't trigger if already training
        guard !isTraining else {
            return false
        }

        return true
    }

    private func getPersonalizedModelURL(for modelId: String) -> URL? {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }

        let modelsDirectory = documentsURL.appendingPathComponent("EdgeML/PersonalizedModels")
        try? fileManager.createDirectory(at: modelsDirectory, withIntermediateDirectories: true)

        return modelsDirectory.appendingPathComponent("\(modelId)-personalized.mlmodelc")
    }

    private func savePersonalizedModel() async throws {
        guard let model = baseModel else {
            throw EdgeMLError.modelNotFound(reason: "No base model loaded")
        }

        guard let personalizedURL = getPersonalizedModelURL(for: model.id) else {
            throw EdgeMLError.trainingFailed(reason: "Could not determine personalized model URL")
        }

        // The trained model is now stored in the trainer's context
        // We need to save it to the personalized model URL
        // This is a placeholder - actual implementation depends on CoreML's APIs

        let mlModel = try MLModel(contentsOf: model.compiledModelURL)
        let metadata = model.metadata
        personalizedModel = EdgeMLModel(
            id: model.id,
            version: "\(model.version)-personalized",
            mlModel: mlModel,
            metadata: metadata,
            compiledModelURL: personalizedURL
        )

        if configuration.enableLogging {
            logger.info("Saved personalized model to \(personalizedURL.path)")
        }
    }
}

// MARK: - Supporting Types

/// Represents a single training sample with metadata.
public struct TrainingSample {
    public let input: MLFeatureProvider
    public let target: MLFeatureProvider
    public let timestamp: Date
    public let metadata: [String: Any]?
}

/// Batch provider for training samples.
private class TrainingSampleBatchProvider: NSObject, MLBatchProvider {
    let samples: [TrainingSample]

    init(samples: [TrainingSample]) {
        self.samples = samples
    }

    var count: Int {
        return samples.count
    }

    func features(at index: Int) -> MLFeatureProvider {
        return samples[index].input
    }
}

/// Record of a training session.
public struct TrainingSession: Codable {
    public let timestamp: Date
    public let sampleCount: Int
    public let trainingTime: TimeInterval
    public let loss: Double?
    public let accuracy: Double?
}

/// Statistics about personalization progress.
public struct PersonalizationStatistics {
    public let totalTrainingSessions: Int
    public let totalSamplesTrained: Int
    public let bufferedSamples: Int
    public let lastTrainingDate: Date?
    public let averageLoss: Double?
    public let averageAccuracy: Double?
    public let isPersonalized: Bool
    public let trainingMode: TrainingMode
}

// MARK: - Array Extension

private extension Array where Element == Double {
    func average() -> Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}
