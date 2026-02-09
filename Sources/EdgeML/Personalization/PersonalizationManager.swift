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

    let configuration: EdgeMLConfiguration
    let trainer: FederatedTrainer
    let logger: Logger

    // Training buffer
    var trainingBuffer: [TrainingSample] = []
    let bufferSizeThreshold: Int
    let minSamplesForTraining: Int

    // Personalized model management
    var personalizedModel: EdgeMLModel?
    var baseModel: EdgeMLModel?
    var trainingHistory: [TrainingSession] = []

    // Ditto mode: separate global model for federation
    fileprivate var globalModel: EdgeMLModel?

    // FedPer mode: layers that are personalized (head) vs shared (body)
    fileprivate var personalizedLayers: Set<String> = []

    // Ditto regularization strength
    fileprivate var lambdaDitto: Double = 0.1

    // State
    var isTraining = false
    var lastTrainingDate: Date?

    // Configuration
    let maxBufferSize: Int
    let trainingInterval: TimeInterval // Minimum time between training sessions
    let trainingMode: TrainingMode
    let uploadThreshold: Int // Number of training sessions before upload

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
}

// MARK: - Model Management

extension PersonalizationManager {

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
                    logger.error(
                        "Failed to load personalized model: \(error.localizedDescription)"
                    )
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
            throw EdgeMLError.trainingFailed(reason: "No base model loaded")
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
}

// MARK: - Statistics & Buffer

extension PersonalizationManager {

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
            trainingMode: trainingMode,
            hasGlobalModel: globalModel != nil,
            personalizedLayerCount: personalizedLayers.count
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
}

// MARK: - Ditto & FedPer Configuration

extension PersonalizationManager {

    /// Configures Ditto mode with the given lambda regularization strength.
    /// - Parameter lambda: Regularization coefficient (higher = personal model stays closer to global).
    public func configureDitto(lambda: Double) {
        self.lambdaDitto = lambda

        // In Ditto mode, the global model is a copy of the base model
        if trainingMode == .ditto, let base = baseModel {
            self.globalModel = base
        }

        if configuration.enableLogging {
            logger.info("Ditto configured with lambda=\(lambda)")
        }
    }

    /// Gets the global model (used in Ditto mode for federation).
    /// In non-Ditto modes, this returns the base model.
    public func getGlobalModel() -> EdgeMLModel? {
        return globalModel ?? baseModel
    }

    /// Updates the global model after a federated round (Ditto mode).
    /// - Parameter model: New global model from server aggregation.
    public func updateGlobalModel(_ model: EdgeMLModel) {
        self.globalModel = model

        if configuration.enableLogging {
            logger.info("Global model updated to version \(model.version)")
        }
    }

    /// Configures FedPer mode by specifying which layers are personalized (head).
    /// - Parameter layers: Set of layer names that form the personalized "head".
    public func configurePersonalizedLayers(_ layers: [String]) {
        self.personalizedLayers = Set(layers)

        if configuration.enableLogging {
            logger.info("FedPer configured with \(layers.count) personalized layers")
        }
    }

    /// Gets the set of personalized layer names (FedPer mode).
    public func getPersonalizedLayerNames() -> Set<String> {
        return personalizedLayers
    }

    /// Applies personalized model state received from the server.
    /// - Parameter response: Personalized model response from GET /api/v1/training/personalized/{device_id}.
    public func applyServerPersonalization(_ response: PersonalizedModelResponse) {
        // Store metrics if available
        if let serverMetrics = response.metrics {
            let session = TrainingSession(
                timestamp: response.updatedAt ?? Date(),
                sampleCount: 0,
                trainingTime: 0,
                loss: serverMetrics["loss"],
                accuracy: serverMetrics["accuracy"]
            )
            trainingHistory.append(session)
        }

        if configuration.enableLogging {
            let strategy = response.strategy ?? "unknown"
            logger.info(
                "Applied server personalization state (strategy: \(strategy))"
            )
        }
    }
}

// MARK: - Private Helpers

extension PersonalizationManager {

    func getPersonalizedModelURL(for modelId: String) -> URL? {
        let fileManager = FileManager.default
        guard let documentsURL = fileManager.urls(
            for: .documentDirectory, in: .userDomainMask
        ).first else {
            return nil
        }

        let modelsDirectory = documentsURL.appendingPathComponent(
            "EdgeML/PersonalizedModels"
        )
        try? fileManager.createDirectory(
            at: modelsDirectory, withIntermediateDirectories: true
        )

        return modelsDirectory.appendingPathComponent(
            "\(modelId)-personalized.mlmodelc"
        )
    }
}
