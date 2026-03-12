import Foundation

/// Result of a control plane synchronization.
///
/// Returned by ``ControlSync/refresh()`` after polling the server for
/// the latest configuration, feature-flag assignments, and rollout state.
public struct ControlSyncResult: Codable, Sendable {
    /// Whether any configuration was updated during this sync.
    public let updated: Bool
    /// The server-side configuration version string.
    public let configVersion: String
    /// Whether feature-flag or experiment assignments changed.
    public let assignmentsChanged: Bool
    /// Whether model rollout state changed.
    public let rolloutsChanged: Bool
    /// Timestamp when the sync completed.
    public let fetchedAt: Date

    enum CodingKeys: String, CodingKey {
        case updated
        case configVersion = "config_version"
        case assignmentsChanged = "assignments_changed"
        case rolloutsChanged = "rollouts_changed"
        case fetchedAt = "fetched_at"
    }

    public init(
        updated: Bool,
        configVersion: String,
        assignmentsChanged: Bool,
        rolloutsChanged: Bool,
        fetchedAt: Date
    ) {
        self.updated = updated
        self.configVersion = configVersion
        self.assignmentsChanged = assignmentsChanged
        self.rolloutsChanged = rolloutsChanged
        self.fetchedAt = fetchedAt
    }
}
