import Foundation
import CoreML

// MARK: - Training

extension EdgeMLClient {

    /// Participates in a federated training round.
    ///
    /// This method:
    /// 1. Downloads the latest model if needed
    /// 2. Trains the model on local data
    /// 3. Extracts weight updates
    /// 4. Uploads updates to the server
    ///
    /// - Parameters:
    ///   - modelId: Identifier of the model to train.
    ///   - dataProvider: Closure that provides training data.
    ///   - config: Training configuration.
    /// - Returns: Result of the training round.
    /// - Throws: `EdgeMLError` if training fails.
    public func participateInRound(
        modelId: String,
        dataProvider: @escaping () -> MLBatchProvider,
        config: TrainingConfig = .standard
    ) async throws -> RoundResult {
        guard let deviceId = self.deviceId else {
            throw EdgeMLError.deviceNotRegistered
        }

        if configuration.enableLogging {
            logger.info("Participating in training round for model: \(modelId)")
        }

        // Get or download model
        let model = try await resolveModelForTraining(modelId: modelId)

        // Train locally
        let trainer = FederatedTrainer(configuration: configuration)
        let trainingResult = try await trainer.train(
            model: model,
            dataProvider: dataProvider,
            config: config
        )

        // Extract and upload weights
        var weightUpdate = try await trainer.extractWeightUpdate(
            model: model,
            trainingResult: trainingResult
        )
        weightUpdate = WeightUpdate(
            modelId: weightUpdate.modelId,
            version: weightUpdate.version,
            deviceId: deviceId,
            weightsData: weightUpdate.weightsData,
            sampleCount: weightUpdate.sampleCount,
            metrics: weightUpdate.metrics,
            roundId: nil
        )

        try await apiClient.uploadWeights(weightUpdate)

        let roundResult = RoundResult(
            roundId: UUID().uuidString,
            trainingResult: trainingResult,
            uploadSucceeded: true,
            completedAt: Date()
        )

        if configuration.enableLogging {
            logger.info("Training round completed: \(trainingResult.sampleCount) samples")
        }

        return roundResult
    }

    /// Trains a model locally without uploading weights.
    ///
    /// Useful for testing and validation.
    ///
    /// - Parameters:
    ///   - model: The model to train.
    ///   - data: Training data provider.
    ///   - config: Training configuration.
    /// - Returns: Training result.
    /// - Throws: `EdgeMLError` if training fails.
    public func trainLocal(
        model: EdgeMLModel,
        data: MLBatchProvider,
        config: TrainingConfig = .standard
    ) async throws -> TrainingResult {
        let trainer = FederatedTrainer(configuration: configuration)
        return try await trainer.train(
            model: model,
            dataProvider: { data },
            config: config
        )
    }
}

// MARK: - Round-Based Training

extension EdgeMLClient {

    /// Checks if a training round is assigned to this device for the given model.
    ///
    /// - Parameter modelId: The model to check for round assignments.
    /// - Returns: Round assignment if available, nil otherwise.
    /// - Throws: `EdgeMLError` if the request fails.
    public func checkRoundAssignment(modelId: String) async throws -> RoundAssignment? {
        guard let deviceId = self.deviceId else {
            throw EdgeMLError.deviceNotRegistered
        }

        return try await apiClient.checkRoundAssignment(deviceId: deviceId, modelId: modelId)
    }

    /// Participates in a specific server-assigned training round.
    ///
    /// This method:
    /// 1. Verifies round assignment
    /// 2. Downloads the model version specified by the round
    /// 3. Trains locally using round config (strategy params, epochs, learning rate)
    /// 4. Applies gradient clipping if configured in the round's filter pipeline
    /// 5. Uploads weight delta with the round ID
    ///
    /// - Parameters:
    ///   - roundId: The round identifier to participate in.
    ///   - modelId: The model to train.
    ///   - dataProvider: Closure that provides training data.
    /// - Returns: Result of the training round.
    /// - Throws: `EdgeMLError` if training fails.
    public func participateInRound(
        roundId: String,
        modelId: String,
        dataProvider: @escaping () -> MLBatchProvider
    ) async throws -> RoundResult {
        guard let deviceId = self.deviceId else {
            throw EdgeMLError.deviceNotRegistered
        }

        if configuration.enableLogging {
            logger.info("Participating in round \(roundId) for model: \(modelId)")
        }

        // Check assignment
        guard let assignment = try await apiClient.checkRoundAssignment(
            deviceId: deviceId, modelId: modelId
        ),
              assignment.roundId == roundId else {
            throw EdgeMLError.noRoundAssignment
        }

        // Download the specific model version for this round
        let model = try await downloadModel(modelId: modelId, version: assignment.modelVersion)

        // Train and upload
        let trainingResult = try await trainForAssignment(
            model: model, assignment: assignment, dataProvider: dataProvider
        )

        let weightsData = try await extractAndClipWeights(
            model: model, assignment: assignment, trainingResult: trainingResult
        )

        try await uploadRoundWeights(
            weightUpdate: weightsData, deviceId: deviceId, roundId: roundId
        )

        let roundResult = RoundResult(
            roundId: roundId,
            trainingResult: trainingResult,
            uploadSucceeded: true,
            completedAt: Date()
        )

        if configuration.enableLogging {
            let strategy = assignment.strategy ?? "fedavg"
            let count = trainingResult.sampleCount
            logger.info(
                "Round \(roundId) completed: \(count) samples, strategy: \(strategy)"
            )
        }

        return roundResult
    }
}

// MARK: - Training Helpers

extension EdgeMLClient {

    fileprivate func trainForAssignment(
        model: EdgeMLModel,
        assignment: RoundAssignment,
        dataProvider: @escaping () -> MLBatchProvider
    ) async throws -> TrainingResult {
        let strategyParams = assignment.strategyParams
        let config = TrainingConfig(
            epochs: strategyParams?.localEpochs ?? 1,
            batchSize: 32,
            learningRate: strategyParams?.learningRate ?? 0.001,
            shuffle: true
        )

        let trainer = FederatedTrainer(configuration: configuration)
        return try await trainer.train(
            model: model,
            dataProvider: dataProvider,
            config: config
        )
    }

    fileprivate func extractAndClipWeights(
        model: EdgeMLModel,
        assignment: RoundAssignment,
        trainingResult: TrainingResult
    ) async throws -> WeightUpdate {
        let trainer = FederatedTrainer(configuration: configuration)
        let weightUpdate = try await trainer.extractWeightUpdate(
            model: model,
            trainingResult: trainingResult
        )

        var clippedWeightsData = weightUpdate.weightsData
        if let clipConfig = assignment.filterConfig?.gradientClip {
            let extractor = WeightExtractor()
            clippedWeightsData = await extractor.applyGradientClipping(
                weightsData: weightUpdate.weightsData,
                maxNorm: clipConfig.maxNorm
            )

            if configuration.enableLogging {
                logger.info("Applied gradient clipping with max_norm=\(clipConfig.maxNorm)")
            }
        }

        return WeightUpdate(
            modelId: weightUpdate.modelId,
            version: weightUpdate.version,
            deviceId: nil,
            weightsData: clippedWeightsData,
            sampleCount: weightUpdate.sampleCount,
            metrics: weightUpdate.metrics,
            roundId: nil
        )
    }

    fileprivate func uploadRoundWeights(
        weightUpdate: WeightUpdate,
        deviceId: String,
        roundId: String
    ) async throws {
        let finalUpdate = WeightUpdate(
            modelId: weightUpdate.modelId,
            version: weightUpdate.version,
            deviceId: deviceId,
            weightsData: weightUpdate.weightsData,
            sampleCount: weightUpdate.sampleCount,
            metrics: weightUpdate.metrics,
            roundId: roundId
        )

        try await apiClient.uploadWeights(finalUpdate)
    }
}
