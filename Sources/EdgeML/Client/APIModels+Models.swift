import Foundation

// API response and request models for the EdgeML server — Model types.

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
