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

// MARK: - Gradient Cache Entry

/// A cached gradient update that has not yet been submitted to the server.
///
/// Used by ``GradientCache`` to persist weight updates across app restarts
/// when network is unavailable or training is interrupted.
public struct GradientCacheEntry: Codable, Sendable {
    /// The round this gradient was computed for.
    public let roundId: String
    /// Model identifier.
    public let modelId: String
    /// Model version at the time of training.
    public let modelVersion: String
    /// Serialized weight delta.
    public let weightsData: Data
    /// Number of local training samples.
    public let sampleCount: Int
    /// When this entry was created.
    public let createdAt: Date
    /// Whether this entry has been successfully submitted to the server.
    public var submitted: Bool

    public init(
        roundId: String,
        modelId: String,
        modelVersion: String,
        weightsData: Data,
        sampleCount: Int,
        createdAt: Date = Date(),
        submitted: Bool = false
    ) {
        self.roundId = roundId
        self.modelId = modelId
        self.modelVersion = modelVersion
        self.weightsData = weightsData
        self.sampleCount = sampleCount
        self.createdAt = createdAt
        self.submitted = submitted
    }
}

// MARK: - Training Eligibility Result

/// Result of a training eligibility check.
public struct EligibilityResult: Sendable {
    /// Whether the device is eligible for training.
    public let eligible: Bool
    /// Reason training was skipped, if not eligible.
    public let reason: IneligibilityReason?

    public init(eligible: Bool, reason: IneligibilityReason? = nil) {
        self.eligible = eligible
        self.reason = reason
    }
}

/// Reason why a device is not eligible for training.
public enum IneligibilityReason: String, Sendable {
    /// Battery level is below the configured minimum.
    case lowBattery
    /// Device is under thermal pressure (serious or critical).
    case thermalPressure
    /// Low Power Mode is enabled.
    case lowPowerMode
    /// Training requires charging but device is not plugged in.
    case notCharging
}

// MARK: - Network Quality

/// Assessment of network suitability for gradient upload.
public struct NetworkQualityResult: Sendable {
    /// Whether the network is suitable for uploading gradients.
    public let suitable: Bool
    /// Reason the network is not suitable, if applicable.
    public let reason: NetworkIneligibilityReason?

    public init(suitable: Bool, reason: NetworkIneligibilityReason? = nil) {
        self.suitable = suitable
        self.reason = reason
    }
}

/// Reason why the network is not suitable for gradient upload.
public enum NetworkIneligibilityReason: String, Sendable {
    /// No network connection available.
    case noConnection
    /// Network connection is expensive (metered/cellular).
    case expensiveNetwork
    /// Network connection is constrained (Low Data Mode).
    case constrainedNetwork
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
