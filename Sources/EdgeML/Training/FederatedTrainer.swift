import Foundation
import CoreML
import os.log

/// Handles on-device federated training with CoreML.
public actor FederatedTrainer {

    // MARK: - Properties

    private let configuration: EdgeMLConfiguration
    private let logger: Logger
    private let weightExtractor: WeightExtractor

    /// Differential privacy engine, created when DP is enabled.
    private var dpEngine: DifferentialPrivacyEngine?

    // Store the update context from the last training session
    private var lastUpdateContext: MLUpdateContext?
    private var originalModelURL: URL?

    // MARK: - Initialization

    /// Creates a new federated trainer.
    /// - Parameter configuration: SDK configuration.
    internal init(configuration: EdgeMLConfiguration) {
        self.configuration = configuration
        self.logger = Logger(subsystem: "ai.edgeml.sdk", category: "FederatedTrainer")
        self.weightExtractor = WeightExtractor()

        let privacyConfig = configuration.privacyConfiguration
        if privacyConfig.enableDifferentialPrivacy {
            self.dpEngine = DifferentialPrivacyEngine(
                config: privacyConfig,
                secureStorage: SecureStorage()
            )
        }
    }

    // MARK: - Training

    /// Trains a model on local data.
    ///
    /// - Parameters:
    ///   - model: The model to train.
    ///   - dataProvider: Closure that provides training data.
    ///   - config: Training configuration.
    /// - Returns: Training result with metrics.
    /// - Throws: `EdgeMLError` if training fails.
    public func train(
        model: EdgeMLModel,
        dataProvider: () -> MLBatchProvider,
        config: TrainingConfig
    ) async throws -> TrainingResult {
        guard model.supportsTraining else {
            throw EdgeMLError.trainingNotSupported
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

        var metrics: [String: Double] = [
            "epochs": Double(config.epochs),
            "batch_size": Double(config.batchSize),
            "learning_rate": config.learningRate,
            "epochs_completed": Double(epochsCompleted),
            "thermal_adjustments_count": Double(ThermalMonitor.shared.thermalAdjustmentCount)
        ]
        if thermalAborted {
            metrics["thermal_aborted"] = 1.0
        }

        let result = TrainingResult(
            sampleCount: data.count,
            loss: loss,
            accuracy: accuracy,
            trainingTime: trainingTime,
            metrics: metrics
        )

        if configuration.enableLogging {
            let thermalInfo = thermalAborted ? " (thermal aborted at epoch \(epochsCompleted)/\(config.epochs))" : ""
            logger.info("Training completed: \(data.count) samples in \(String(format: "%.2f", trainingTime))s\(thermalInfo)")
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
    /// - Throws: `EdgeMLError` if extraction fails.
    public func extractWeightUpdate(
        model: EdgeMLModel,
        trainingResult: TrainingResult
    ) async throws -> WeightUpdate {
        guard let updateContext = lastUpdateContext else {
            throw EdgeMLError.trainingFailed(reason: "No training context available. Train the model first.")
        }

        if configuration.enableLogging {
            logger.info("Extracting weight updates...")
        }

        // Pass DP engine to weight extractor if configured
        await weightExtractor.setDPEngine(dpEngine)

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

        // Merge DP metadata into training metrics
        var metrics = trainingResult.metrics
        let dpResultVal = await weightExtractor.dpResult
        if let dpRes = dpResultVal {
            metrics["dp_epsilon_used"] = dpRes.epsilonUsed
            metrics["dp_clipping_norm"] = dpRes.clippingNorm
            metrics["dp_noise_scale"] = dpRes.noiseScale
            metrics["dp_mechanism"] = dpRes.mechanism == .gaussian ? 0.0 : 1.0
        }

        if configuration.enableLogging {
            logger.info("Weight extraction completed: \(weightsData.count) bytes (\(updateFormat))")
        }

        return WeightUpdate(
            modelId: model.id,
            version: model.version,
            deviceId: nil,
            weightsData: weightsData,
            sampleCount: trainingResult.sampleCount,
            metrics: metrics,
            dpEpsilonUsed: dpResultVal?.epsilonUsed,
            dpNoiseScale: dpResultVal?.noiseScale,
            dpMechanism: dpResultVal?.mechanism.rawValue,
            dpClippingNorm: dpResultVal?.clippingNorm
        )
    }

    // MARK: - Private Methods

    /// Number of epochs actually completed (may differ from requested if thermal-aborted).
    private(set) var epochsCompleted: Int = 0

    /// Whether training was aborted due to thermal state.
    private(set) var thermalAborted: Bool = false

    private func performTraining(
        modelURL: URL,
        trainingData: MLBatchProvider,
        config: TrainingConfig
    ) async throws -> MLUpdateContext {
        self.currentTrainingConfig = config
        self.epochsCompleted = 0
        self.thermalAborted = false

        let thermalPolicy = configuration.training.thermalPolicy
        let thermalMonitor = ThermalMonitor.shared

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
            // Check thermal state before each epoch
            let adjustments = thermalMonitor.getAdjustments(for: thermalPolicy)

            if adjustments.shouldAbort {
                if configuration.enableLogging {
                    logger.warning("Training aborted due to thermal state: \(thermalMonitor.currentState.rawValue)")
                }
                thermalAborted = true
                thermalMonitor.recordAdjustment()
                break
            }

            // Apply epoch delay if thermal state warrants it
            if adjustments.epochDelayMs > 0 {
                if configuration.enableLogging {
                    logger.info("Thermal delay: \(adjustments.epochDelayMs)ms before epoch \(epoch)")
                }
                thermalMonitor.recordAdjustment()
                try await Task.sleep(nanoseconds: adjustments.epochDelayMs * 1_000_000)
            }

            let context = try await runSingleUpdatePass(
                modelURL: currentModelURL,
                trainingData: trainingData,
                config: config,
                epoch: epoch
            )

            lastContext = context
            epochsCompleted += 1

            // For subsequent epochs, write the updated model to a temp location
            if epoch < config.epochs - 1 {
                let tempURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("edgeml-epoch-\(epoch)-\(UUID().uuidString)")
                    .appendingPathExtension("mlmodelc")
                try context.model.write(to: tempURL)
                tempURLs.append(tempURL)
                currentModelURL = tempURL
            }
        }

        guard let finalContext = lastContext else {
            throw EdgeMLError.trainingFailed(reason: "No training epochs completed")
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
                            continuation.resume(throwing: EdgeMLError.trainingFailed(
                                reason: context.task.error?.localizedDescription ?? "Unknown training error"
                            ))
                        @unknown default:
                            continuation.resume(throwing: EdgeMLError.trainingFailed(reason: "Unexpected task state"))
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
                continuation.resume(throwing: EdgeMLError.trainingFailed(reason: error.localizedDescription))
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
    /// - Throws: `EdgeMLError` if no training context is available or write fails.
    public func saveTrainedModel(to url: URL) async throws {
        guard let context = lastUpdateContext else {
            throw EdgeMLError.trainingFailed(reason: "No training context available")
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
