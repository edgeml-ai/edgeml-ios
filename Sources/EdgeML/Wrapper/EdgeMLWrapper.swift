import CoreML
import Foundation
import os.log

/// Namespace for the EdgeML drop-in CoreML wrapper.
///
/// Use ``wrap(_:modelId:config:)`` to add EdgeML telemetry, validation,
/// and OTA updates to any existing ``MLModel`` with a single line change:
///
/// ```swift
/// // Before
/// let model = try MLModel(contentsOf: modelURL)
///
/// // After
/// let model = try EdgeML.wrap(MLModel(contentsOf: modelURL), modelId: "classifier")
///
/// // Call sites stay identical
/// let result = try model.prediction(from: input)
/// ```
public enum EdgeML {

    private static let logger = Logger(subsystem: "ai.edgeml.sdk", category: "EdgeML")

    /// Wraps an existing CoreML model with EdgeML telemetry, input
    /// validation, and OTA update support.
    ///
    /// The returned ``EdgeMLWrappedModel`` mirrors every ``MLModel``
    /// prediction method so existing call sites require zero changes.
    ///
    /// - Parameters:
    ///   - model: A compiled ``MLModel`` to wrap.
    ///   - modelId: The model identifier registered on the EdgeML server.
    ///   - config: Configuration controlling validation, telemetry, and OTA
    ///     behaviour.  Defaults to ``EdgeMLWrapperConfig/default``.
    /// - Returns: A wrapped model ready for prediction.
    /// - Throws: Never under normal circumstances.  Reserved for future
    ///   config validation errors.
    public static func wrap(
        _ model: MLModel,
        modelId: String,
        config: EdgeMLWrapperConfig = .default
    ) throws -> EdgeMLWrappedModel {
        let telemetry = TelemetryQueue(
            modelId: modelId,
            serverURL: config.serverURL,
            apiKey: config.apiKey,
            batchSize: config.telemetryBatchSize,
            flushInterval: config.telemetryFlushInterval
        )

        // Build a contract from the CoreML model description so validation
        // works out of the box even without a server-side contract.
        let inputNames = Set(model.modelDescription.inputDescriptionsByName.keys)
        let outputNames = Set(model.modelDescription.outputDescriptionsByName.keys)
        let localContract = WrappedModelContract(
            inputFeatureNames: inputNames,
            outputFeatureNames: outputNames
        )

        let wrapped = EdgeMLWrappedModel(
            model: model,
            modelId: modelId,
            config: config,
            telemetry: telemetry,
            serverContract: localContract
        )

        logger.info("Wrapped model \(modelId) with \(inputNames.count) inputs, \(outputNames.count) outputs")

        // Kick off non-blocking OTA check if enabled
        if config.otaUpdatesEnabled {
            wrapped.checkForUpdates()
        }

        return wrapped
    }
}
