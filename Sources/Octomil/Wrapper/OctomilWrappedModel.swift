import CoreML
import Foundation
import os.log

/// Drop-in replacement for ``MLModel`` that adds Octomil telemetry,
/// contract validation, and OTA model updates.
///
/// ``OctomilWrappedModel`` is **not** a subclass of ``MLModel`` (which is
/// final), but it exposes the same prediction API so call sites require
/// zero changes beyond model construction:
///
/// ```swift
/// // Before
/// let model = try MLModel(contentsOf: url)
/// let result = try model.prediction(from: input)
///
/// // After
/// let model = try Octomil.wrap(MLModel(contentsOf: url), modelId: "classifier")
/// let result = try model.prediction(from: input)
/// ```
///
/// Each prediction call:
/// 1. Validates the input against the server model contract (if available)
/// 2. Records wall-clock latency
/// 3. Delegates to the underlying ``MLModel``
/// 4. Queues a telemetry event
public final class OctomilWrappedModel: @unchecked Sendable {

    // MARK: - Properties

    /// The CoreML model that performs inference.
    public private(set) var underlyingModel: MLModel

    /// Model identifier registered with the Octomil server.
    public let modelId: String

    /// Active wrapper configuration.
    public let config: OctomilWrapperConfig

    /// The wrapper model contract, if one was fetched or set.
    /// Used for input validation before prediction.
    public internal(set) var serverContract: WrappedModelContract?

    /// Telemetry queue for batched inference event reporting.
    public let telemetry: TelemetryQueue

    /// The model description from the underlying CoreML model.
    public var modelDescription: MLModelDescription {
        underlyingModel.modelDescription
    }

    private let logger: Logger

    // MARK: - Initialization

    /// Creates a wrapped model.
    ///
    /// Prefer using ``Octomil/wrap(_:modelId:config:)`` instead of calling
    /// this initializer directly.
    ///
    /// - Parameters:
    ///   - model: The CoreML model to wrap.
    ///   - modelId: Model identifier on the Octomil server.
    ///   - config: Wrapper configuration.
    ///   - telemetry: Telemetry queue (created automatically when `nil`).
    ///   - serverContract: Optional pre-loaded contract.
    public init(
        model: MLModel,
        modelId: String,
        config: OctomilWrapperConfig = .default,
        telemetry: TelemetryQueue? = nil,
        serverContract: WrappedModelContract? = nil
    ) {
        self.underlyingModel = model
        self.modelId = modelId
        self.config = config
        self.serverContract = serverContract
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "WrappedModel")

        self.telemetry = telemetry ?? TelemetryQueue(
            modelId: modelId,
            serverURL: config.serverURL,
            apiKey: config.apiKey,
            batchSize: config.telemetryBatchSize,
            flushInterval: config.telemetryFlushInterval
        )
    }

    // MARK: - Prediction (MLModel-compatible API)

    /// Makes a prediction using the wrapped CoreML model.
    ///
    /// - Parameter input: An ``MLFeatureProvider`` with the input features.
    /// - Returns: The model's prediction output.
    /// - Throws: ``FeatureValidationError`` if validation is enabled and
    ///   the input doesn't match the contract, or any error from CoreML.
    public func prediction(from input: MLFeatureProvider) throws -> MLFeatureProvider {
        try validateIfNeeded(input)

        let start = CFAbsoluteTimeGetCurrent()
        do {
            let result = try underlyingModel.prediction(from: input)
            let latencyMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            recordTelemetry(latencyMs: latencyMs, success: true)
            return result
        } catch {
            let latencyMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            recordTelemetry(latencyMs: latencyMs, success: false, error: error)
            throw error
        }
    }

    /// Makes a prediction with the given options.
    ///
    /// - Parameters:
    ///   - input: An ``MLFeatureProvider`` with the input features.
    ///   - options: Prediction options (e.g. compute units).
    /// - Returns: The model's prediction output.
    public func prediction(
        from input: MLFeatureProvider,
        options: MLPredictionOptions
    ) throws -> MLFeatureProvider {
        try validateIfNeeded(input)

        let start = CFAbsoluteTimeGetCurrent()
        do {
            let result = try underlyingModel.prediction(from: input, options: options)
            let latencyMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            recordTelemetry(latencyMs: latencyMs, success: true)
            return result
        } catch {
            let latencyMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            recordTelemetry(latencyMs: latencyMs, success: false, error: error)
            throw error
        }
    }

    /// Makes batch predictions.
    ///
    /// - Parameter batch: A batch of input feature providers.
    /// - Returns: A batch of predictions.
    public func predictions(from batch: MLBatchProvider) throws -> MLBatchProvider {
        let start = CFAbsoluteTimeGetCurrent()
        do {
            let result = try underlyingModel.predictions(from: batch, options: MLPredictionOptions())
            let latencyMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            recordTelemetry(latencyMs: latencyMs, success: true)
            return result
        } catch {
            let latencyMs = (CFAbsoluteTimeGetCurrent() - start) * 1000
            recordTelemetry(latencyMs: latencyMs, success: false, error: error)
            throw error
        }
    }

    // MARK: - OTA Updates

    /// Replaces the underlying model with a new version.
    ///
    /// This is called internally when an OTA update is detected, but can
    /// also be called manually.
    ///
    /// - Parameter newModel: The new CoreML model.
    public func replaceModel(_ newModel: MLModel) {
        underlyingModel = newModel
        logger.info("Replaced underlying model for \(self.modelId)")
    }

    /// Manually triggers an async check for OTA model updates.
    ///
    /// This is a no-op if `config.otaUpdatesEnabled` is false or
    /// no server URL is configured.
    public func checkForUpdates() {
        guard config.otaUpdatesEnabled, config.serverURL != nil else { return }
        Task.detached(priority: .utility) { [weak self] in
            await self?.performOTACheck()
        }
    }

    // MARK: - Persist

    /// Persists any unsent telemetry events to disk.
    ///
    /// Call this from your ``UIApplicationDelegate/applicationDidEnterBackground(_:)``
    /// or equivalent to avoid losing events.
    public func persistTelemetry() {
        telemetry.persistEvents()
    }

    // MARK: - Private

    private func validateIfNeeded(_ input: MLFeatureProvider) throws {
        guard config.validateInputs, let contract = serverContract else { return }
        try contract.validate(input: input)
    }

    private func recordTelemetry(latencyMs: Double, success: Bool, error: Error? = nil) {
        guard config.telemetryEnabled else { return }
        if success {
            telemetry.recordSuccess(latencyMs: latencyMs)
        } else {
            telemetry.recordFailure(
                latencyMs: latencyMs,
                error: error?.localizedDescription ?? "unknown"
            )
        }
    }

    private func performOTACheck() async {
        // Placeholder for OTA update logic.
        // In a full implementation this would:
        // 1. Call the server's model versions endpoint
        // 2. Compare with the current model version
        // 3. Download and compile the new model
        // 4. Call replaceModel(_:)
        logger.debug("OTA update check for \(self.modelId) (not yet implemented)")
    }
}

// MARK: - Wrapped Model Contract

/// Describes the feature-name contract used for ``MLFeatureProvider`` input validation.
///
/// Unlike ``ServerModelContract`` (which validates raw float arrays against
/// tensor shapes from the server), this validates ``MLFeatureProvider`` inputs
/// by checking that all required feature names are present.
public struct WrappedModelContract: Sendable {

    /// Expected input feature names.
    public let inputFeatureNames: Set<String>

    /// Expected output feature names.
    public let outputFeatureNames: Set<String>

    /// Model version this contract belongs to.
    public let version: String?

    public init(
        inputFeatureNames: Set<String>,
        outputFeatureNames: Set<String> = [],
        version: String? = nil
    ) {
        self.inputFeatureNames = inputFeatureNames
        self.outputFeatureNames = outputFeatureNames
        self.version = version
    }

    /// Validates that an ``MLFeatureProvider`` contains all required input
    /// features.
    ///
    /// - Parameter input: The feature provider to validate.
    /// - Throws: ``FeatureValidationError`` if required features are missing.
    public func validate(input: MLFeatureProvider) throws {
        let provided = input.featureNames
        let missing = inputFeatureNames.subtracting(provided)
        guard missing.isEmpty else {
            throw FeatureValidationError(
                missingFeatures: missing,
                providedFeatures: provided,
                expectedFeatures: inputFeatureNames
            )
        }
    }
}

/// Error thrown when feature-name validation fails on an ``OctomilWrappedModel``.
public struct FeatureValidationError: LocalizedError, Sendable {

    /// Feature names required by the contract but absent in the input.
    public let missingFeatures: Set<String>

    /// Feature names that were provided.
    public let providedFeatures: Set<String>

    /// Feature names expected by the contract.
    public let expectedFeatures: Set<String>

    public var errorDescription: String? {
        let sorted = missingFeatures.sorted()
        return "Contract validation failed: missing features \(sorted). "
            + "Expected \(expectedFeatures.sorted()), got \(providedFeatures.sorted())."
    }
}
