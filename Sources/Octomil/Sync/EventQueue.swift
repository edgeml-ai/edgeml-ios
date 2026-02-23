import Foundation
import os.log

/// An event waiting to be synced.
public struct QueuedEvent: Codable, Sendable {
    /// Unique event ID.
    public let id: String
    /// Event type (e.g., "inference", "training_started", "training_completed").
    public let type: String
    /// Event timestamp (milliseconds since epoch).
    public let timestamp: Int64
    /// Numeric metrics.
    public let metrics: [String: Double]?
    /// String metadata.
    public let metadata: [String: String]?

    public init(
        id: String = UUID().uuidString,
        type: String,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        metrics: [String: Double]? = nil,
        metadata: [String: String]? = nil
    ) {
        self.id = id
        self.type = type
        self.timestamp = timestamp
        self.metrics = metrics
        self.metadata = metadata
    }
}

/// Queue for offline event storage.
///
/// Stores training events and metrics when offline for later sync.
/// Events are persisted as JSON files in Application Support.
public actor EventQueue {

    // MARK: - Properties

    private let queueDir: URL
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder
    private let logger: Logger
    private let maxQueueSize = 1000

    // MARK: - Singleton

    /// Shared instance for the default queue directory.
    public static let shared = EventQueue()

    // MARK: - Initialization

    /// Creates an event queue with the default directory.
    public init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.queueDir = appSupport.appendingPathComponent("octomil_event_queue", isDirectory: true)
        self.jsonEncoder = JSONEncoder()
        self.jsonDecoder = JSONDecoder()
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "EventQueue")

        try? FileManager.default.createDirectory(at: queueDir, withIntermediateDirectories: true)
    }

    /// Creates an event queue with a custom directory (for testing).
    internal init(queueDir: URL) {
        self.queueDir = queueDir
        self.jsonEncoder = JSONEncoder()
        self.jsonDecoder = JSONDecoder()
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "EventQueue")

        try? FileManager.default.createDirectory(at: queueDir, withIntermediateDirectories: true)
    }

    // MARK: - Public Methods

    /// Adds an event to the queue.
    /// - Parameter event: The event to add.
    /// - Returns: True if added successfully.
    @discardableResult
    public func addEvent(_ event: QueuedEvent) -> Bool {
        do {
            // Enforce max queue size with FIFO eviction
            let files = try eventFiles()
            if files.count >= maxQueueSize,
               let oldest = files.min(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                try? FileManager.default.removeItem(at: oldest)
            }

            let data = try jsonEncoder.encode(event)
            let fileURL = queueDir.appendingPathComponent("\(event.id).json")
            try data.write(to: fileURL, options: .atomic)
            return true
        } catch {
            logger.warning("Failed to queue event: \(error.localizedDescription)")
            return false
        }
    }

    /// Adds a simple training event.
    /// - Parameters:
    ///   - type: Event type string.
    ///   - metrics: Optional numeric metrics.
    ///   - metadata: Optional string metadata.
    /// - Returns: True if added successfully.
    @discardableResult
    public func addTrainingEvent(
        type: String,
        metrics: [String: Double]? = nil,
        metadata: [String: String]? = nil
    ) -> Bool {
        let event = QueuedEvent(
            type: type,
            metrics: metrics,
            metadata: metadata
        )
        return addEvent(event)
    }

    /// Gets all pending events sorted by timestamp.
    /// - Returns: List of queued events.
    public func getPendingEvents() -> [QueuedEvent] {
        do {
            let files = try eventFiles()
            return files.compactMap { fileURL -> QueuedEvent? in
                guard let data = try? Data(contentsOf: fileURL) else { return nil }
                return try? jsonDecoder.decode(QueuedEvent.self, from: data)
            }.sorted { $0.timestamp < $1.timestamp }
        } catch {
            logger.warning("Failed to read event queue: \(error.localizedDescription)")
            return []
        }
    }

    /// Removes an event from the queue.
    /// - Parameter eventId: The event ID to remove.
    /// - Returns: True if removed successfully.
    @discardableResult
    public func removeEvent(_ eventId: String) -> Bool {
        let fileURL = queueDir.appendingPathComponent("\(eventId).json")
        do {
            try FileManager.default.removeItem(at: fileURL)
            return true
        } catch {
            return false
        }
    }

    /// Gets the current queue size.
    /// - Returns: Number of events in the queue.
    public func getQueueSize() -> Int {
        return (try? eventFiles().count) ?? 0
    }

    /// Clears all events from the queue.
    public func clear() {
        guard let files = try? eventFiles() else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    // MARK: - Private

    private func eventFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: queueDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
    }
}
