import Foundation
import CoreML
import os.log

/// Handles on-device federated training with CoreML.
public actor FederatedTrainer {

    // MARK: - Properties

    private let configuration: OctomilConfiguration
    private let logger: Logger
    private let weightExtractor: WeightExtractor

    // Store the update context from the last training session
    private var lastUpdateContext: MLUpdateContext?
    private var originalModelURL: URL?

    // MARK: - Initialization

    /// Creates a new federated trainer.
    /// - Parameter configuration: SDK configuration.
    internal init(configuration: OctomilConfiguration) {
        self.configuration = configuration
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "FederatedTrainer")
        self.weightExtractor = WeightExtractor()
    }

    // MARK: - Training

    /// Trains a model on local data.
    ///
    /// - Parameters:
    ///   - model: The model to train.
    ///   - dataProvider: Closure that provides training data.
    ///   - config: Training configuration.
    /// - Returns: Training result with metrics.
    /// - Throws: `OctomilError` if training fails.
    public func train(
        model: OctomilModel,
        dataProvider: () -> MLBatchProvider,
        config: TrainingConfig
    ) async throws -> TrainingResult {
        guard model.supportsTraining else {
            throw OctomilError.trainingNotSupported
        }

        if configuration.enableLogging {
            logger.info("Starting local training...")
        }

        let startTime = Date()
        let data = dataProvider()

        // Store original model URL for delta computation
        self.originalModelURL = model.compiledModelURL

        // Create update task
        let updateContext = try await performTraining(
            modelURL: model.compiledModelURL,
            trainingData: data,
            config: config
        )

        // Store update context for weight extraction
        self.lastUpdateContext = updateContext

        let trainingTime = Date().timeIntervalSince(startTime)

        // Extract metrics from context
        let loss = extractLoss(from: updateContext)
        let accuracy = extractAccuracy(from: updateContext)

        let result = TrainingResult(
            sampleCount: data.count,
            loss: loss,
            accuracy: accuracy,
            trainingTime: trainingTime,
            metrics: [
                "epochs": Double(config.epochs),
                "batch_size": Double(config.batchSize),
                "learning_rate": config.learningRate
            ]
        )

        if configuration.enableLogging {
            logger.info("Training completed: \(data.count) samples in \(String(format: "%.2f", trainingTime))s")
        }

        return result
    }

    /// Trains a model only if the device is eligible based on battery, thermal, and network state.
    ///
    /// Checks device eligibility first. If ineligible, caches the intent and returns nil.
    /// If eligible, performs training via ``train(model:dataProvider:config:)`` and
    /// optionally caches the resulting gradient for later upload if the network is unsuitable.
    ///
    /// - Parameters:
    ///   - model: The model to train.
    ///   - dataProvider: Closure that provides training data.
    ///   - config: Training configuration.
    ///   - deviceState: Current device state snapshot.
    ///   - gradientCache: Optional gradient cache for persisting results offline.
    ///   - networkMonitor: Network monitor to assess upload suitability.
    /// - Returns: Training result if training was performed, nil if skipped.
    public func trainIfEligible(
        model: OctomilModel,
        dataProvider: () -> MLBatchProvider,
        config: TrainingConfig,
        deviceState: DeviceStateMonitor.DeviceState,
        gradientCache: GradientCache? = nil,
        networkMonitor: NetworkMonitor = .shared
    ) async throws -> TrainingResult? {
        let eligibility = TrainingEligibility.check(
            deviceState: deviceState,
            policy: configuration.training
        )

        guard eligibility.eligible else {
            if configuration.enableLogging {
                logger.info("Training skipped: \(eligibility.reason?.rawValue ?? "unknown")")
            }
            return nil
        }

        let result = try await train(
            model: model,
            dataProvider: dataProvider,
            config: config
        )

        // Cache gradient if network is not suitable for immediate upload
        if let cache = gradientCache {
            let networkQuality = TrainingEligibility.assessNetworkQuality(
                isConnected: networkMonitor.isConnected,
                isExpensive: networkMonitor.isExpensive,
                isConstrained: networkMonitor.isConstrained
            )
            if !networkQuality.suitable {
                let weightUpdate = try await extractWeightUpdate(
                    model: model,
                    trainingResult: result
                )
                let entry = GradientCacheEntry(
                    roundId: UUID().uuidString,
                    modelId: model.id,
                    modelVersion: model.version,
                    weightsData: weightUpdate.weightsData,
                    sampleCount: result.sampleCount
                )
                await cache.store(entry)

                if configuration.enableLogging {
                    logger.info("Gradient cached for later upload: \(networkQuality.reason?.rawValue ?? "unknown network issue")")
                }
            }
        }

        return result
    }

    /// Extracts weight updates from a trained model.
    ///
    /// Attempts to extract weight deltas (updated - original) when possible.
    /// Falls back to full weight extraction if delta computation is not supported.
    ///
    /// **Note:** CoreML doesn't expose model weights directly for most models.
    /// For best results, ensure your model is created with updatable parameters.
    ///
    /// - Parameters:
    ///   - model: The original model.
    ///   - trainingResult: Result from training.
    /// - Returns: Weight update for upload.
    /// - Throws: `OctomilError` if extraction fails.
    public func extractWeightUpdate(
        model: OctomilModel,
        trainingResult: TrainingResult
    ) async throws -> WeightUpdate {
        guard let updateContext = lastUpdateContext else {
            throw OctomilError.trainingFailed(reason: "No training context available. Train the model first.")
        }

        if configuration.enableLogging {
            logger.info("Extracting weight updates...")
        }

        // Try to extract weight delta
        var weightsData: Data
        var updateFormat: String = "weights" // default to full weights

        if let originalURL = originalModelURL {
            // Try delta extraction first
            do {
                weightsData = try await weightExtractor.extractWeightDelta(
                    originalModelURL: originalURL,
                    updatedContext: updateContext
                )
                updateFormat = "delta"

                if configuration.enableLogging {
                    logger.info("Successfully extracted weight delta")
                }
            } catch {
                // Fall back to full weights if delta extraction fails
                if configuration.enableLogging {
                    logger.warning("Delta extraction failed, falling back to full weights: \(error.localizedDescription)")
                }

                weightsData = try await weightExtractor.extractFullWeights(
                    updatedContext: updateContext
                )
            }
        } else {
            // No original model URL, extract full weights
            weightsData = try await weightExtractor.extractFullWeights(
                updatedContext: updateContext
            )
        }

        // Metrics are already in the correct format from training result
        let metrics = trainingResult.metrics

        if configuration.enableLogging {
            logger.info("Weight extraction completed: \(weightsData.count) bytes (\(updateFormat))")
        }

        return WeightUpdate(
            modelId: model.id,
            version: model.version,
            deviceId: nil,
            weightsData: weightsData,
            sampleCount: trainingResult.sampleCount,
            metrics: metrics
        )
    }

    // MARK: - Private Methods

    private func performTraining(
        modelURL: URL,
        trainingData: MLBatchProvider,
        config: TrainingConfig
    ) async throws -> MLUpdateContext {
        self.currentTrainingConfig = config

        // CoreML's MLUpdateTask runs one "update pass" as defined in the model's
        // compiled training spec. For multi-epoch training, we chain update tasks:
        // each subsequent task uses the model from the previous task's context.
        var currentModelURL = modelURL
        var lastContext: MLUpdateContext?
        var tempURLs: [URL] = []

        defer {
            // Clean up intermediate epoch models
            for url in tempURLs {
                try? FileManager.default.removeItem(at: url)
            }
        }

        for epoch in 0..<max(config.epochs, 1) {
            let context = try await runSingleUpdatePass(
                modelURL: currentModelURL,
                trainingData: trainingData,
                config: config,
                epoch: epoch
            )

            lastContext = context

            // For subsequent epochs, write the updated model to a temp location
            if epoch < config.epochs - 1 {
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("octomil-epoch-\(epoch)-\(UUID().uuidString)")
                    .appendingPathExtension("mlmodelc")
                try context.model.write(to: tempURL)
                tempURLs.append(tempURL)
                currentModelURL = tempURL
            }
        }

        guard let finalContext = lastContext else {
            throw OctomilError.trainingFailed(reason: "No training epochs completed")
        }

        return finalContext
    }

    /// Runs a single MLUpdateTask pass and returns the update context.
    private func runSingleUpdatePass(
        modelURL: URL,
        trainingData: MLBatchProvider,
        config: TrainingConfig,
        epoch: Int
    ) async throws -> MLUpdateContext {
        return try await withCheckedThrowingContinuation { [self] continuation in
            do {
                let parameters = try self.configureTrainingParameters(config: config)

                let progressHandlers = MLUpdateProgressHandlers(
                    forEvents: [.trainingBegin, .epochEnd],
                    progressHandler: { [self] context in
                        if self.configuration.enableLogging {
                            if let loss = context.metrics[.lossValue] as? Double {
                                self.logger.debug("Epoch \(epoch): loss = \(String(format: "%.6f", loss))")
                            } else {
                                self.logger.debug("Epoch \(epoch) completed")
                            }
                        }
                    },
                    completionHandler: { context in
                        switch context.task.state {
                        case .completed:
                            continuation.resume(returning: context)
                        case .failed:
                            continuation.resume(throwing: OctomilError.trainingFailed(
                                reason: context.task.error?.localizedDescription ?? "Unknown training error"
                            ))
                        @unknown default:
                            continuation.resume(throwing: OctomilError.trainingFailed(reason: "Unexpected task state"))
                        }
                    }
                )

                let updateTask = try MLUpdateTask(
                    forModelAt: modelURL,
                    trainingData: trainingData,
                    configuration: parameters,
                    progressHandlers: progressHandlers
                )

                updateTask.resume()

            } catch {
                continuation.resume(throwing: OctomilError.trainingFailed(reason: error.localizedDescription))
            }
        }
    }

    private func configureTrainingParameters(config: TrainingConfig) throws -> MLModelConfiguration {
        let modelConfig = MLModelConfiguration()
        modelConfig.computeUnits = .all

        // Training hyperparameters (epochs, learning rate, batch size) are
        // typically compiled into the .mlmodelc via coremltools updateable spec.
        // The TrainingConfig is used for logging and the epochs override below.

        if configuration.enableLogging {
            logger.info("""
                Training config: epochs=\(config.epochs), \
                batchSize=\(config.batchSize), \
                learningRate=\(config.learningRate)
                """)
        }

        return modelConfig
    }

    /// Number of epochs for the current training config. MLUpdateTask uses the
    /// model's compiled epoch count, but we can control this by running
    /// multiple single-epoch update tasks in sequence when needed.
    private var currentTrainingConfig: TrainingConfig?

    /// Saves the trained model from the last update context to the given URL.
    ///
    /// - Parameter url: Destination URL for the compiled model.
    /// - Throws: `OctomilError` if no training context is available or write fails.
    public func saveTrainedModel(to url: URL) async throws {
        guard let context = lastUpdateContext else {
            throw OctomilError.trainingFailed(reason: "No training context available")
        }

        // Remove existing file if present
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        try context.model.write(to: url)

        if configuration.enableLogging {
            logger.info("Saved trained model to \(url.path)")
        }
    }

    private func extractLoss(from context: MLUpdateContext) -> Double? {
        // MLUpdateContext.metrics uses MLMetricKey keys
        if let lossValue = context.metrics[.lossValue] as? Double {
            return lossValue
        }
        return nil
    }

    private func extractAccuracy(from context: MLUpdateContext) -> Double? {
        // Check all metrics for accuracy-related keys
        // CoreML doesn't have a standard accuracy key, but custom models may report it
        for (key, value) in context.metrics {
            let keyStr = String(describing: key)
            if keyStr.lowercased().contains("accuracy"), let doubleVal = value as? Double {
                return doubleVal
            }
        }
        return nil
    }
}
