import Foundation

// MARK: - Upload Policy

/// Controls whether and how weight updates are uploaded after training.
///
/// This is the single knob developers use to decide upload behavior:
/// - ``auto``: Upload automatically after training completes (default for federated mode).
/// - ``manual``: Train locally and return the ``WeightUpdate`` without uploading.
///   The developer can inspect, transform, or upload it themselves.
/// - ``disabled``: Local-only training. No weight data is prepared for upload.
public enum UploadPolicy: String, Codable, Sendable {
    /// Upload weight updates automatically after training completes.
    ///
    /// If a roundId is provided, uploads to that round (with SecAgg if enabled).
    /// Otherwise uploads as an ad-hoc update.
    case auto

    /// Train locally and return weight updates without uploading.
    ///
    /// Use this when you need to inspect or transform weights before upload,
    /// or when you want full control over upload timing.
    case manual

    /// Local-only training. No weight extraction or upload.
    ///
    /// Use this for pure on-device personalization where model
    /// improvements never leave the device.
    case disabled
}

// MARK: - Training Outcome

/// Result of the unified ``OctomilClient/train`` method.
///
/// Combines training metrics, optional weight update, and upload status
/// into a single result type.
public struct TrainingOutcome: Sendable {
    /// Local training metrics (loss, accuracy, timing).
    public let trainingResult: TrainingResult

    /// Extracted weight update, or nil if ``UploadPolicy/disabled``.
    public let weightUpdate: WeightUpdate?

    /// Whether the update was uploaded to the server.
    public let uploaded: Bool

    /// Whether secure aggregation was used for the upload.
    public let secureAggregation: Bool

    /// The upload policy that was used.
    public let uploadPolicy: UploadPolicy

    /// Whether training ran in degraded mode (forward-pass only, no gradient updates).
    ///
    /// When true, the model's weights were NOT updated on-device. The loss and accuracy
    /// metrics reflect inference on training data, not actual learning. To enable real
    /// on-device training, ensure your CoreML model is exported as updatable.
    public let degraded: Bool

    public init(
        trainingResult: TrainingResult,
        weightUpdate: WeightUpdate? = nil,
        uploaded: Bool = false,
        secureAggregation: Bool = false,
        uploadPolicy: UploadPolicy = .disabled,
        degraded: Bool = false
    ) {
        self.trainingResult = trainingResult
        self.weightUpdate = weightUpdate
        self.uploaded = uploaded
        self.secureAggregation = secureAggregation
        self.uploadPolicy = uploadPolicy
        self.degraded = degraded
    }
}

// MARK: - Missing Training Signature Error

/// Error thrown when a model lacks training support and
/// ``OctomilConfiguration/allowDegradedTraining`` is false (the default).
///
/// To fix this, export your CoreML model as updatable:
/// ```python
/// import coremltools as ct
/// spec = ct.utils.load_spec("model.mlmodel")
/// builder = ct.models.neural_network.NeuralNetworkBuilder(spec=spec)
/// builder.make_updatable(["layer_name"])
/// ct.utils.save_spec(spec, "updatable_model.mlmodel")
/// ```
///
/// Or set `allowDegradedTraining = true` in configuration to permit forward-pass-only training.
public struct MissingTrainingSignatureError: LocalizedError, Sendable {
    /// Available signature or capability keys on this model.
    public let availableSignatures: [String]

    public var errorDescription: String? {
        "Model does not support on-device training and cannot perform gradient updates. " +
        "Available signatures: \(availableSignatures). " +
        "Either export your model as updatable " +
        "or set allowDegradedTraining = true to permit forward-pass-only training."
    }

    public init(availableSignatures: [String]) {
        self.availableSignatures = availableSignatures
    }
}
