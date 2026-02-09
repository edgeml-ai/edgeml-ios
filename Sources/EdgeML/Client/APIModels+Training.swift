import Foundation

// API response and request models for the EdgeML server — Training, Round, Personalization, and Event types.

// MARK: - Training

/// Configuration for a training round.
public struct TrainingConfig: Codable, Sendable {
    /// Number of local epochs.
    public let epochs: Int
    /// Batch size for training.
    public let batchSize: Int
    /// Learning rate.
    public let learningRate: Double
    /// Whether to shuffle data.
    public let shuffle: Bool

    public init(
        epochs: Int = 1,
        batchSize: Int = 32,
        learningRate: Double = 0.001,
        shuffle: Bool = true
    ) {
        self.epochs = epochs
        self.batchSize = batchSize
        self.learningRate = learningRate
        self.shuffle = shuffle
    }

    /// Default training configuration.
    public static let standard = TrainingConfig()
}

/// Result of a training round.
public struct TrainingResult: Codable, Sendable {
    /// Number of samples used for training.
    public let sampleCount: Int
    /// Training loss.
    public let loss: Double?
    /// Training accuracy if applicable.
    public let accuracy: Double?
    /// Time taken for training in seconds.
    public let trainingTime: TimeInterval
    /// Additional metrics.
    public let metrics: [String: Double]

    enum CodingKeys: String, CodingKey {
        case sampleCount = "sample_count"
        case loss
        case accuracy
        case trainingTime = "training_time"
        case metrics
    }
}

/// Result of participating in a federated round.
public struct RoundResult: Codable, Sendable {
    /// Round identifier.
    public let roundId: String
    /// Training result.
    public let trainingResult: TrainingResult
    /// Whether weights were uploaded successfully.
    public let uploadSucceeded: Bool
    /// Timestamp of completion.
    public let completedAt: Date

    enum CodingKeys: String, CodingKey {
        case roundId = "round_id"
        case trainingResult = "training_result"
        case uploadSucceeded = "upload_succeeded"
        case completedAt = "completed_at"
    }
}

/// Weight update to be uploaded to server.
public struct WeightUpdate: Codable, Sendable {
    /// Model identifier.
    public let modelId: String
    /// Model version.
    public let version: String
    /// Server-assigned device UUID (optional).
    public let deviceId: String?
    /// Compressed weight delta.
    public let weightsData: Data
    /// Number of samples used.
    public let sampleCount: Int
    /// Training metrics.
    public let metrics: [String: Double]
    /// Round identifier (for round-based training).
    public let roundId: String?

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case version
        case deviceId = "device_id"
        case weightsData = "weights_data"
        case sampleCount = "sample_count"
        case metrics
        case roundId = "round_id"
    }
}

// MARK: - Events

/// Event to track on the server.
public struct TrackingEvent: Codable, Sendable {
    /// Event name.
    public let name: String
    /// Event properties.
    public let properties: [String: String]
    /// Timestamp.
    public let timestamp: Date

    public init(name: String, properties: [String: String] = [:], timestamp: Date = Date()) {
        self.name = name
        self.properties = properties
        self.timestamp = timestamp
    }
}

// MARK: - Round Management

/// Request to check for round assignments.
public struct RoundAssignmentRequest: Codable, Sendable {
    /// Device ID.
    public let deviceId: String
    /// Model ID to check.
    public let modelId: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case modelId = "model_id"
    }
}

/// Response from round assignment check.
public struct RoundAssignment: Codable, Sendable {
    /// Round identifier.
    public let roundId: String
    /// Model ID for this round.
    public let modelId: String
    /// Model version to train against.
    public let modelVersion: String
    /// Training strategy (e.g., "fedavg", "fedprox", "ditto").
    public let strategy: String?
    /// Strategy-specific parameters.
    public let strategyParams: RoundStrategyParams?
    /// Round status.
    public let status: String
    /// Filter/pipeline configuration from server.
    public let filterConfig: RoundFilterConfig?

    enum CodingKeys: String, CodingKey {
        case roundId = "round_id"
        case modelId = "model_id"
        case modelVersion = "model_version"
        case strategy
        case strategyParams = "strategy_params"
        case status
        case filterConfig = "filter_config"
    }
}

/// Strategy-specific parameters sent by the server in a round config.
public struct RoundStrategyParams: Codable, Sendable {
    /// Proximal term weight for FedProx.
    public let proximalMu: Double?
    /// Ditto regularization coefficient.
    public let lambdaDitto: Double?
    /// Layers considered "head" (personalized) for FedPer.
    public let personalizedLayers: [String]?
    /// Local epochs override from server.
    public let localEpochs: Int?
    /// Learning rate override from server.
    public let learningRate: Double?

    enum CodingKeys: String, CodingKey {
        case proximalMu = "proximal_mu"
        case lambdaDitto = "lambda_ditto"
        case personalizedLayers = "personalized_layers"
        case localEpochs = "local_epochs"
        case learningRate = "learning_rate"
    }
}

/// Filter pipeline configuration from server round config.
public struct RoundFilterConfig: Codable, Sendable {
    /// Gradient clipping configuration.
    public let gradientClip: GradientClipConfig?

    enum CodingKeys: String, CodingKey {
        case gradientClip = "gradient_clip"
    }
}

/// Gradient clipping parameters.
public struct GradientClipConfig: Codable, Sendable {
    /// Maximum L2 norm for gradient clipping.
    public let maxNorm: Double

    enum CodingKeys: String, CodingKey {
        case maxNorm = "max_norm"
    }
}

/// Response when no round is assigned.
public struct RoundAssignmentResponse: Codable, Sendable {
    /// The assignment if one is available.
    public let assignment: RoundAssignment?
}

// MARK: - Personalization

/// Response containing personalized model state from the server.
public struct PersonalizedModelResponse: Codable, Sendable {
    /// Device ID.
    public let deviceId: String
    /// Model ID.
    public let modelId: String
    /// Personalized weights data (base64 encoded from server, decoded to Data).
    public let weightsData: Data?
    /// Strategy used (e.g., "ditto", "fedper").
    public let strategy: String?
    /// Metrics associated with the personalized model.
    public let metrics: [String: Double]?
    /// When the personalized state was last updated.
    public let updatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case modelId = "model_id"
        case weightsData = "weights_data"
        case strategy
        case metrics
        case updatedAt = "updated_at"
    }
}

/// Request to upload personalized model update.
public struct PersonalizedUpdateRequest: Codable, Sendable {
    /// Device ID.
    public let deviceId: String
    /// Model ID.
    public let modelId: String
    /// Personalized weights data.
    public let weightsData: Data
    /// Training metrics.
    public let metrics: [String: Double]
    /// Strategy used.
    public let strategy: String?

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case modelId = "model_id"
        case weightsData = "weights_data"
        case metrics
        case strategy
    }
}

// MARK: - Inference Events

/// Metrics payload for an inference event.
public struct InferenceEventMetrics: Codable, Sendable {
    public var ttfcMs: Double?
    public var chunkIndex: Int?
    public var chunkLatencyMs: Double?
    public var totalChunks: Int?
    public var totalDurationMs: Double?
    public var throughput: Double?

    enum CodingKeys: String, CodingKey {
        case ttfcMs = "ttfc_ms"
        case chunkIndex = "chunk_index"
        case chunkLatencyMs = "chunk_latency_ms"
        case totalChunks = "total_chunks"
        case totalDurationMs = "total_duration_ms"
        case throughput
    }

    public init(
        ttfcMs: Double? = nil,
        chunkIndex: Int? = nil,
        chunkLatencyMs: Double? = nil,
        totalChunks: Int? = nil,
        totalDurationMs: Double? = nil,
        throughput: Double? = nil
    ) {
        self.ttfcMs = ttfcMs
        self.chunkIndex = chunkIndex
        self.chunkLatencyMs = chunkLatencyMs
        self.totalChunks = totalChunks
        self.totalDurationMs = totalDurationMs
        self.throughput = throughput
    }
}

/// Identifies the device, model, and session for an inference event.
public struct InferenceEventContext: Codable, Sendable {
    public let deviceId: String
    public let modelId: String
    public let version: String
    public let modality: String
    public let sessionId: String

    enum CodingKeys: String, CodingKey {
        case deviceId = "device_id"
        case modelId = "model_id"
        case version
        case modality
        case sessionId = "session_id"
    }

    public init(deviceId: String, modelId: String, version: String, modality: String, sessionId: String) {
        self.deviceId = deviceId
        self.modelId = modelId
        self.version = version
        self.modality = modality
        self.sessionId = sessionId
    }
}

/// Request body for ``POST /api/v1/inference/events``.
public struct InferenceEventRequest: Codable, Sendable {
    public let context: InferenceEventContext
    public let eventType: String
    public let timestampMs: Int64
    public var metrics: InferenceEventMetrics?
    public var orgId: String?

    enum CodingKeys: String, CodingKey {
        case eventType = "event_type"
        case timestampMs = "timestamp_ms"
        case metrics
        case orgId = "org_id"
    }

    public init(
        context: InferenceEventContext,
        eventType: String,
        timestampMs: Int64,
        metrics: InferenceEventMetrics? = nil,
        orgId: String? = nil
    ) {
        self.context = context
        self.eventType = eventType
        self.timestampMs = timestampMs
        self.metrics = metrics
        self.orgId = orgId
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try context.encode(to: encoder)
        try container.encode(eventType, forKey: .eventType)
        try container.encode(timestampMs, forKey: .timestampMs)
        try container.encodeIfPresent(metrics, forKey: .metrics)
        try container.encodeIfPresent(orgId, forKey: .orgId)
    }

    public init(from decoder: Decoder) throws {
        self.context = try InferenceEventContext(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.eventType = try container.decode(String.self, forKey: .eventType)
        self.timestampMs = try container.decode(Int64.self, forKey: .timestampMs)
        self.metrics = try container.decodeIfPresent(InferenceEventMetrics.self, forKey: .metrics)
        self.orgId = try container.decodeIfPresent(String.self, forKey: .orgId)
    }
}
