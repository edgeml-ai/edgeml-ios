import Foundation

/// API response and request models for the EdgeML server.

// MARK: - Device Registration

/// Request body for device registration.
/// Aligns with server's DeviceRegistrationRequest schema.
public struct DeviceRegistrationRequest: Codable, Sendable {
    /// Client-provided device identifier (e.g., IDFV on iOS).
    public let deviceIdentifier: String
    /// Organization identifier.
    public let orgId: String
    /// Device platform (ios, android, python).
    public let platform: String
    /// Operating system version.
    public let osVersion: String?
    /// EdgeML SDK version.
    public let sdkVersion: String?
    /// Host application version.
    public let appVersion: String?
    /// Device hardware info.
    public let deviceInfo: DeviceInfoRequest?
    /// Device locale (e.g., "en_US").
    public let locale: String?
    /// Device region/country code.
    public let region: String?
    /// Device timezone.
    public let timezone: String?
    /// Additional device metadata.
    public let metadata: [String: String]?
    /// ML-specific capabilities.
    public let capabilities: DeviceCapabilities?

    enum CodingKeys: String, CodingKey {
        case deviceIdentifier = "device_identifier"
        case orgId = "org_id"
        case platform
        case osVersion = "os_version"
        case sdkVersion = "sdk_version"
        case appVersion = "app_version"
        case deviceInfo = "device_info"
        case locale
        case region
        case timezone
        case metadata
        case capabilities
    }
}

/// Device hardware info (nested under device_info).
public struct DeviceInfoRequest: Codable, Sendable {
    /// Device manufacturer (e.g., "Apple").
    public let manufacturer: String?
    /// Device model (e.g., "iPhone 15").
    public let model: String?
    /// CPU architecture (e.g., "arm64").
    public let cpuArchitecture: String?
    /// Whether GPU/NPU is available.
    public let gpuAvailable: Bool
    /// Total RAM in megabytes.
    public let totalMemoryMb: Int?
    /// Available storage in megabytes.
    public let availableStorageMb: Int?

    enum CodingKeys: String, CodingKey {
        case manufacturer
        case model
        case cpuArchitecture = "cpu_architecture"
        case gpuAvailable = "gpu_available"
        case totalMemoryMb = "total_memory_mb"
        case availableStorageMb = "available_storage_mb"
    }
}

/// Device capabilities for ML operations.
public struct DeviceCapabilities: Codable, Sendable {
    /// Whether device supports on-device training.
    public let supportsTraining: Bool
    /// CoreML version available (iOS only).
    public let coremlVersion: String?
    /// Whether Neural Engine is available.
    public let hasNeuralEngine: Bool
    /// Maximum batch size supported.
    public let maxBatchSize: Int?
    /// Supported model formats.
    public let supportedFormats: [String]?

    enum CodingKeys: String, CodingKey {
        case supportsTraining = "supports_training"
        case coremlVersion = "coreml_version"
        case hasNeuralEngine = "has_neural_engine"
        case maxBatchSize = "max_batch_size"
        case supportedFormats = "supported_formats"
    }

    public init(
        supportsTraining: Bool = true,
        coremlVersion: String? = nil,
        hasNeuralEngine: Bool = false,
        maxBatchSize: Int? = nil,
        supportedFormats: [String]? = nil
    ) {
        self.supportsTraining = supportsTraining
        self.coremlVersion = coremlVersion
        self.hasNeuralEngine = hasNeuralEngine
        self.maxBatchSize = maxBatchSize
        self.supportedFormats = supportedFormats
    }
}

/// Response from device registration.
public struct DeviceRegistrationResponse: Codable, Sendable {
    /// Server-assigned UUID for this device.
    public let id: String
    /// Client-provided device identifier.
    public let deviceIdentifier: String
    /// Organization identifier.
    public let orgId: String
    /// Device status.
    public let status: String
    /// When the device was registered.
    public let registeredAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case deviceIdentifier = "device_identifier"
        case orgId = "org_id"
        case status
        case registeredAt = "registered_at"
    }
}

// MARK: - Device Heartbeat

/// Request body for device heartbeat.
public struct HeartbeatRequest: Codable, Sendable {
    /// Optional metadata to merge with existing device metadata.
    public let metadata: [String: String]?

    enum CodingKeys: String, CodingKey {
        case metadata
    }

    public init(
        metadata: [String: String]? = nil
    ) {
        self.metadata = metadata
    }
}

/// Response from device heartbeat.
public struct HeartbeatResponse: Codable, Sendable {
    /// Device ID.
    public let id: String
    /// Client device identifier.
    public let deviceIdentifier: String
    /// Device status after heartbeat.
    public let status: String
    /// Last heartbeat timestamp.
    public let lastHeartbeat: Date

    enum CodingKeys: String, CodingKey {
        case id
        case deviceIdentifier = "device_identifier"
        case status
        case lastHeartbeat = "last_heartbeat"
    }
}

// MARK: - Device Groups

/// A device group for targeting.
public struct DeviceGroup: Codable, Sendable {
    /// Group UUID.
    public let id: String
    /// Group name.
    public let name: String
    /// Optional description.
    public let description: String?
    /// Group type (static, dynamic, hybrid).
    public let groupType: String
    /// Whether group is active.
    public let isActive: Bool
    /// Number of devices in group.
    public let deviceCount: Int
    /// Group tags.
    public let tags: [String]?
    /// When group was created.
    public let createdAt: Date
    /// When group was last updated.
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case description
        case groupType = "group_type"
        case isActive = "is_active"
        case deviceCount = "device_count"
        case tags
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

/// Response containing device's group memberships.
public struct DeviceGroupsResponse: Codable, Sendable {
    /// List of groups device belongs to.
    public let groups: [DeviceGroup]
}

// MARK: - Device Info

/// Full device information from server.
public struct DeviceInfo: Codable, Sendable {
    /// Server-assigned UUID.
    public let id: String
    /// Client-provided device identifier.
    public let deviceIdentifier: String
    /// Organization ID.
    public let orgId: String
    /// Platform.
    public let platform: String
    /// OS version.
    public let osVersion: String?
    /// SDK version.
    public let sdkVersion: String?
    /// App version.
    public let appVersion: String?
    /// Status.
    public let status: String
    /// Manufacturer.
    public let manufacturer: String?
    /// Model.
    public let model: String?
    /// CPU architecture.
    public let cpuArchitecture: String?
    /// GPU available.
    public let gpuAvailable: Bool
    /// Total memory MB.
    public let totalMemoryMb: Int?
    /// Available storage MB.
    public let availableStorageMb: Int?
    /// Locale.
    public let locale: String?
    /// Region.
    public let region: String?
    /// Timezone.
    public let timezone: String?
    /// Last heartbeat.
    public let lastHeartbeat: Date?
    /// Heartbeat interval.
    public let heartbeatIntervalSeconds: Int
    /// Capabilities.
    public let capabilities: [String: String]?
    /// Created at.
    public let createdAt: Date
    /// Updated at.
    public let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case deviceIdentifier = "device_identifier"
        case orgId = "org_id"
        case platform
        case osVersion = "os_version"
        case sdkVersion = "sdk_version"
        case appVersion = "app_version"
        case status
        case manufacturer
        case model
        case cpuArchitecture = "cpu_architecture"
        case gpuAvailable = "gpu_available"
        case totalMemoryMb = "total_memory_mb"
        case availableStorageMb = "available_storage_mb"
        case locale
        case region
        case timezone
        case lastHeartbeat = "last_heartbeat"
        case heartbeatIntervalSeconds = "heartbeat_interval_seconds"
        case capabilities
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

// MARK: - Model Metadata

/// Metadata about a model version.
public struct ModelMetadata: Codable, Sendable {
    /// Model identifier.
    public let modelId: String
    /// Version string.
    public let version: String
    /// SHA256 checksum of the model file.
    public let checksum: String
    /// File size in bytes.
    public let fileSize: UInt64
    /// When this version was created.
    public let createdAt: Date
    /// Model format.
    public let format: String
    /// Whether training is supported.
    public let supportsTraining: Bool
    /// Model description.
    public let description: String?
    /// Input schema.
    public let inputSchema: [String: String]?
    /// Output schema.
    public let outputSchema: [String: String]?

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case version
        case checksum
        case fileSize = "file_size"
        case createdAt = "created_at"
        case format
        case supportsTraining = "supports_training"
        case description
        case inputSchema = "input_schema"
        case outputSchema = "output_schema"
    }
}

/// Response schema for a model version (server API).
public struct ModelVersionResponse: Codable, Sendable {
    public let modelId: String
    public let version: String
    public let checksum: String
    public let sizeBytes: UInt64
    public let format: String
    public let description: String?
    public let createdAt: Date
    public let metrics: [String: AnyCodable]?

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case version
        case checksum
        case sizeBytes = "size_bytes"
        case format
        case description
        case createdAt = "created_at"
        case metrics
    }
}

/// Minimal AnyCodable wrapper for decoding metrics.
public struct AnyCodable: Codable, Sendable {
    public let value: Any

    public init(_ value: Any) {
        self.value = value
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let intVal = try? container.decode(Int.self) {
            value = intVal
        } else if let doubleVal = try? container.decode(Double.self) {
            value = doubleVal
        } else if let boolVal = try? container.decode(Bool.self) {
            value = boolVal
        } else if let stringVal = try? container.decode(String.self) {
            value = stringVal
        } else if let dictVal = try? container.decode([String: AnyCodable].self) {
            value = dictVal.mapValues { $0.value }
        } else if let arrayVal = try? container.decode([AnyCodable].self) {
            value = arrayVal.map { $0.value }
        } else {
            value = NSNull()
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch value {
        case let intVal as Int:
            try container.encode(intVal)
        case let doubleVal as Double:
            try container.encode(doubleVal)
        case let boolVal as Bool:
            try container.encode(boolVal)
        case let stringVal as String:
            try container.encode(stringVal)
        case let dictVal as [String: Any]:
            let encoded = dictVal.mapValues { AnyCodable($0) }
            try container.encode(encoded)
        case let arrayVal as [Any]:
            let encoded = arrayVal.map { AnyCodable($0) }
            try container.encode(encoded)
        default:
            try container.encodeNil()
        }
    }
}

/// Information about a model update.
public struct ModelUpdateInfo: Codable, Sendable {
    /// The new version available.
    public let newVersion: String
    /// Current version on device.
    public let currentVersion: String
    /// Whether update is required.
    public let isRequired: Bool
    /// Release notes for the update.
    public let releaseNotes: String?
    /// Size of the update in bytes.
    public let updateSize: UInt64

    enum CodingKeys: String, CodingKey {
        case newVersion = "new_version"
        case currentVersion = "current_version"
        case isRequired = "is_required"
        case releaseNotes = "release_notes"
        case updateSize = "update_size"
    }
}

// MARK: - Version Resolution

/// Response from version resolution endpoint.
public struct VersionResolutionResponse: Codable, Sendable {
    /// Resolved version string.
    public let version: String
    /// Source of the resolution.
    public let source: String
    /// Experiment ID if applicable.
    public let experimentId: String?
    /// Rollout ID if applicable.
    public let rolloutId: Int?
    /// Device bucket for debugging.
    public let deviceBucket: Int?

    enum CodingKeys: String, CodingKey {
        case version
        case source
        case experimentId = "experiment_id"
        case rolloutId = "rollout_id"
        case deviceBucket = "device_bucket"
    }
}

/// Response with download URL.
public struct DownloadURLResponse: Codable, Sendable {
    /// Pre-signed download URL.
    public let url: String
    /// URL expiration time.
    public let expiresAt: Date
    /// File checksum for verification.
    public let checksum: String
    /// File size in bytes.
    public let fileSize: UInt64

    enum CodingKeys: String, CodingKey {
        case url
        case expiresAt = "expires_at"
        case checksum
        case fileSize = "file_size"
    }
}

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

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case version
        case deviceId = "device_id"
        case weightsData = "weights_data"
        case sampleCount = "sample_count"
        case metrics
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

// MARK: - Secure Aggregation

/// Response from the server when setting up a SecAgg session.
public struct SecAggSessionResponse: Codable, Sendable {
    /// Server-assigned session identifier.
    public let sessionId: String
    /// Round identifier.
    public let roundId: String
    /// This client's 1-based participant index.
    public let clientIndex: Int
    /// Minimum shares needed for reconstruction.
    public let threshold: Int
    /// Total participants in this session.
    public let totalClients: Int
    /// Privacy budget.
    public let privacyBudget: Double
    /// Key length in bits.
    public let keyLength: Int

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case roundId = "round_id"
        case clientIndex = "client_index"
        case threshold
        case totalClients = "total_clients"
        case privacyBudget = "privacy_budget"
        case keyLength = "key_length"
    }
}

/// Request to submit key shares during SecAgg Phase 1.
public struct SecAggShareKeysRequest: Codable, Sendable {
    /// Session identifier.
    public let sessionId: String
    /// Device identifier.
    public let deviceId: String
    /// Base64-encoded serialized share bundles.
    public let sharesData: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case deviceId = "device_id"
        case sharesData = "shares_data"
    }
}

/// Request to submit masked model update during SecAgg Phase 2.
public struct SecAggMaskedInputRequest: Codable, Sendable {
    /// Session identifier.
    public let sessionId: String
    /// Device identifier.
    public let deviceId: String
    /// Base64-encoded masked weight data.
    public let maskedWeightsData: String
    /// Number of training samples used.
    public let sampleCount: Int
    /// Training metrics.
    public let metrics: [String: Double]

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case deviceId = "device_id"
        case maskedWeightsData = "masked_weights_data"
        case sampleCount = "sample_count"
        case metrics
    }
}

/// Request to submit unmasking shares during SecAgg Phase 3.
public struct SecAggUnmaskRequest: Codable, Sendable {
    /// Session identifier.
    public let sessionId: String
    /// Device identifier.
    public let deviceId: String
    /// Base64-encoded unmasking share data.
    public let unmaskData: String

    enum CodingKeys: String, CodingKey {
        case sessionId = "session_id"
        case deviceId = "device_id"
        case unmaskData = "unmask_data"
    }
}

/// Server response when requesting unmasking, includes dropped client indices.
public struct SecAggUnmaskResponse: Codable, Sendable {
    /// Indices of clients that dropped out.
    public let droppedClientIndices: [Int]
    /// Whether unmasking is needed.
    public let unmaskingRequired: Bool

    enum CodingKeys: String, CodingKey {
        case droppedClientIndices = "dropped_client_indices"
        case unmaskingRequired = "unmasking_required"
    }
}

// MARK: - Error Response

/// Error response from the server.
public struct APIErrorResponse: Codable, Sendable {
    /// Error detail message.
    public let detail: String
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
