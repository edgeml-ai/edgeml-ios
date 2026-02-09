import Foundation
import CoreML
import os.log

/// Handles on-device federated training with CoreML.
public actor FederatedTrainer {

    // MARK: - Properties

    private let configuration: EdgeMLConfiguration
    private let logger: Logger
    private let weightExtractor: WeightExtractor

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
        return try await withCheckedThrowingContinuation { [self] continuation in
            do {
                // Configure training parameters
                let parameters = try self.configureTrainingParameters(config: config)

                // Create update task
                let progressHandlers = MLUpdateProgressHandlers(
                    forEvents: [.epochEnd],
                    progressHandler: { contextProgress in
                        let progress = contextProgress.progress
                        if self.configuration.enableLogging {
                            self.logger.debug("Training progress: \(Int(progress.fractionCompleted * 100))%")
                        }
                    },
                    completionHandler: { context in
                        switch context.task.state {
                        case .completed:
                            continuation.resume(returning: context)
                        case .failed:
                            continuation.resume(throwing: EdgeMLError.trainingFailed(
                                reason: context.task.error?.localizedDescription ?? "Unknown error"
                            ))
                        @unknown default:
                            continuation.resume(throwing: EdgeMLError.trainingFailed(reason: "Unexpected state"))
                        }
                    }
                )

                let updateTask = try MLUpdateTask(
                    forModelAt: modelURL,
                    trainingData: trainingData,
                    configuration: parameters,
                    progressHandlers: progressHandlers
                )

                // Start training
                updateTask.resume()

            } catch {
                continuation.resume(throwing: EdgeMLError.trainingFailed(reason: error.localizedDescription))
            }
        }
    }

    private func configureTrainingParameters(config: TrainingConfig) throws -> MLModelConfiguration {
        let modelConfig = MLModelConfiguration()
        modelConfig.computeUnits = .all

        // Note: In a real implementation, you would set up MLUpdateProgressHandlers
        // and configure epochs, learning rate, etc. through the appropriate APIs
        // The exact API depends on the model's training configuration

        return modelConfig
    }

    private func extractLoss(from context: MLUpdateContext) -> Double? {
        // Extract loss from update context metrics
        if let metrics = context.metrics[.lossValue] {
            return metrics as? Double
        }
        return nil
    }

    private func extractAccuracy(from context: MLUpdateContext) -> Double? {
        // Check if accuracy metric is available
        // This depends on the model's configuration
        return nil
    }
}

// MARK: - MLUpdateContext Extension

extension MLUpdateContext {
    /// Available metric keys
    enum MetricKey: String {
        case lossValue = "MLMetricKeyLossValue"
    }

    /// Get metrics by key
    var metrics: [MetricKey: Any] {
        // In a real implementation, you would access the context's metrics
        // This is a simplified placeholder
        return [:]
    }
}
