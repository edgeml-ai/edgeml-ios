import Foundation
import CoreML

// MARK: - Training Data Collection

extension PersonalizationManager {

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
                logger.warning(
                    "Training buffer exceeded max size, removed oldest samples"
                )
            }
        }

        // Check if we should trigger training
        if shouldTriggerTraining() {
            try await trainIncrementally()
        }
    }

    /// Adds multiple training samples at once.
    public func addTrainingSamples(
        _ samples: [(input: MLFeatureProvider, target: MLFeatureProvider)]
    ) async throws {
        for (input, target) in samples {
            try await addTrainingSample(input: input, target: target)
        }
    }
}

// MARK: - Incremental Training

extension PersonalizationManager {

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
                let count = trainingBuffer.count
                let min = minSamplesForTraining
                logger.debug(
                    "Not enough samples for training (\(count) < \(min))"
                )
            }
            return
        }

        guard let model = getCurrentModel() else {
            throw EdgeMLError.trainingFailed(
                reason: "No model available for training"
            )
        }

        isTraining = true
        defer { isTraining = false }

        let result = try await performIncrementalTraining(on: model)
        recordTrainingSession(result: result)
    }

    /// Forces training on current buffer, regardless of thresholds.
    public func forceTraining() async throws {
        guard !trainingBuffer.isEmpty else {
            throw EdgeMLError.trainingFailed(
                reason: "No training samples in buffer"
            )
        }

        try await trainIncrementally()
    }
}

// MARK: - Training Helpers

extension PersonalizationManager {

    fileprivate func shouldTriggerTraining() -> Bool {
        guard trainingBuffer.count >= bufferSizeThreshold else { return false }
        guard trainingBuffer.count >= minSamplesForTraining else { return false }

        if let lastDate = lastTrainingDate {
            guard Date().timeIntervalSince(lastDate) >= trainingInterval else {
                return false
            }
        }

        guard !isTraining else { return false }
        return true
    }

    fileprivate func savePersonalizedModel() async throws {
        guard let model = baseModel else {
            throw EdgeMLError.trainingFailed(reason: "No base model loaded")
        }

        guard let personalizedURL = getPersonalizedModelURL(
            for: model.id
        ) else {
            throw EdgeMLError.trainingFailed(
                reason: "Could not determine personalized model URL"
            )
        }

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
            logger.info(
                "Saved personalized model to \(personalizedURL.path)"
            )
        }
    }

    fileprivate func performIncrementalTraining(
        on model: EdgeMLModel
    ) async throws -> TrainingResult {
        if configuration.enableLogging {
            logger.info(
                "Starting incremental training with \(self.trainingBuffer.count) samples"
            )
        }

        let batchProvider = TrainingSampleBatchProvider(
            samples: trainingBuffer
        )

        let config = TrainingConfig(
            epochs: 1,
            batchSize: min(trainingBuffer.count, 32),
            learningRate: 0.0001
        )

        let result = try await trainer.train(
            model: model,
            dataProvider: { batchProvider },
            config: config
        )

        try await savePersonalizedModel()
        return result
    }

    fileprivate func recordTrainingSession(result: TrainingResult) {
        let session = TrainingSession(
            timestamp: Date(),
            sampleCount: trainingBuffer.count,
            trainingTime: result.trainingTime,
            loss: result.loss,
            accuracy: result.accuracy
        )
        trainingHistory.append(session)

        trainingBuffer.removeAll()
        lastTrainingDate = Date()

        if configuration.enableLogging {
            let time = String(format: "%.2f", session.trainingTime)
            logger.info("Incremental training completed in \(time)s")
        }

        if trainingMode.uploadsToServer
            && trainingHistory.count >= uploadThreshold
            && configuration.enableLogging {
            let count = trainingHistory.count
            let mode = trainingMode.rawValue
            logger.info(
                "Upload threshold reached (\(count) sessions) - mode: \(mode)"
            )
        }
    }
}
