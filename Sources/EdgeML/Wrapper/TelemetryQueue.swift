import Foundation
import os.log

/// A single inference telemetry event.
public struct InferenceTelemetryEvent: Codable, Sendable {
    /// Model identifier.
    public let modelId: String
    /// Inference latency in milliseconds.
    public let latencyMs: Double
    /// Millisecond-precision Unix timestamp.
    public let timestamp: Int64
    /// Whether the prediction succeeded.
    public let success: Bool
    /// Optional error message on failure.
    public let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case latencyMs = "latency_ms"
        case timestamp
        case success
        case errorMessage = "error_message"
    }

    public init(
        modelId: String,
        latencyMs: Double,
        timestamp: Int64 = Int64(Date().timeIntervalSince1970 * 1000),
        success: Bool = true,
        errorMessage: String? = nil
    ) {
        self.modelId = modelId
        self.latencyMs = latencyMs
        self.timestamp = timestamp
        self.success = success
        self.errorMessage = errorMessage
    }
}

/// Batches inference telemetry events and sends them to the EdgeML server.
///
/// Events are accumulated in memory and flushed either when the batch size
/// is reached or when a periodic timer fires.  Unsent events are persisted
/// to disk so they survive app termination and can be retried on next launch.
public final class TelemetryQueue: @unchecked Sendable {

    // MARK: - Properties

    private let modelId: String
    private let serverURL: URL?
    private let apiKey: String?
    private let batchSize: Int
    private let flushInterval: TimeInterval
    private let logger: Logger

    private let lock = NSLock()
    private var buffer: [InferenceTelemetryEvent] = []
    private var flushTimer: DispatchSourceTimer?
    private let timerQueue = DispatchQueue(label: "ai.edgeml.telemetry.timer")
    private let persistenceURL: URL

    /// Current number of buffered (unsent) events.
    public var pendingCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return buffer.count
    }

    // MARK: - Initialization

    /// Creates a telemetry queue.
    ///
    /// - Parameters:
    ///   - modelId: The model identifier for this queue.
    ///   - serverURL: Base URL for the telemetry endpoint.
    ///   - apiKey: API key for authentication.
    ///   - batchSize: Flush when this many events have accumulated.
    ///   - flushInterval: Maximum seconds between automatic flushes.
    public init(
        modelId: String,
        serverURL: URL? = nil,
        apiKey: String? = nil,
        batchSize: Int = 50,
        flushInterval: TimeInterval = 30
    ) {
        self.modelId = modelId
        self.serverURL = serverURL
        self.apiKey = apiKey
        self.batchSize = max(batchSize, 1)
        self.flushInterval = flushInterval
        self.logger = Logger(subsystem: "ai.edgeml.sdk", category: "TelemetryQueue")

        // Persistence location
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.persistenceURL = appSupport
            .appendingPathComponent("edgeml_telemetry", isDirectory: true)
            .appendingPathComponent("\(modelId)_events.json")

        try? FileManager.default.createDirectory(
            at: persistenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        restorePersistedEvents()
        startFlushTimer()
    }

    /// Creates a telemetry queue using an explicit persistence URL (for testing).
    internal init(
        modelId: String,
        serverURL: URL?,
        apiKey: String?,
        batchSize: Int,
        flushInterval: TimeInterval,
        persistenceURL: URL
    ) {
        self.modelId = modelId
        self.serverURL = serverURL
        self.apiKey = apiKey
        self.batchSize = max(batchSize, 1)
        self.flushInterval = flushInterval
        self.logger = Logger(subsystem: "ai.edgeml.sdk", category: "TelemetryQueue")
        self.persistenceURL = persistenceURL

        try? FileManager.default.createDirectory(
            at: persistenceURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        restorePersistedEvents()
        startFlushTimer()
    }

    deinit {
        flushTimer?.cancel()
        persistEvents()
    }

    // MARK: - Public API

    /// Records a single inference event.
    ///
    /// When the buffer reaches ``batchSize`` the queue is flushed
    /// automatically in the background.
    public func record(_ event: InferenceTelemetryEvent) {
        lock.lock()
        buffer.append(event)
        let shouldFlush = buffer.count >= batchSize
        lock.unlock()

        if shouldFlush {
            flushAsync()
        }
    }

    /// Convenience to record a successful inference.
    public func recordSuccess(latencyMs: Double) {
        record(InferenceTelemetryEvent(modelId: modelId, latencyMs: latencyMs))
    }

    /// Convenience to record a failed inference.
    public func recordFailure(latencyMs: Double, error: String) {
        record(InferenceTelemetryEvent(
            modelId: modelId,
            latencyMs: latencyMs,
            success: false,
            errorMessage: error
        ))
    }

    /// Forces an immediate async flush of all buffered events.
    public func flushAsync() {
        Task.detached(priority: .utility) { [weak self] in
            await self?.flush()
        }
    }

    /// Persists unsent events to disk.
    ///
    /// Call this when the app moves to the background to avoid losing events.
    public func persistEvents() {
        lock.lock()
        let snapshot = buffer
        lock.unlock()

        guard !snapshot.isEmpty else { return }

        do {
            let data = try JSONEncoder().encode(snapshot)
            try data.write(to: persistenceURL, options: .atomic)
        } catch {
            logger.warning("Failed to persist telemetry events: \(error.localizedDescription)")
        }
    }

    // MARK: - Internal / Private

    /// Sends all buffered events to the server and clears the buffer.
    internal func flush() async {
        let batch = drainBuffer()

        guard !batch.isEmpty else { return }

        guard let serverURL else {
            // No server configured -- discard events silently.
            logger.debug("No server URL configured; discarding \(batch.count) telemetry events")
            return
        }

        let url = serverURL.appendingPathComponent("api/v1/telemetry/inference")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("edgeml-ios/1.0", forHTTPHeaderField: "User-Agent")
        if let apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        do {
            let encoder = JSONEncoder()
            request.httpBody = try encoder.encode(TelemetryBatchPayload(modelId: modelId, events: batch))

            let (_, response) = try await URLSession.shared.data(for: request)
            if let httpResponse = response as? HTTPURLResponse,
               !(200...299).contains(httpResponse.statusCode) {
                logger.warning("Telemetry upload returned HTTP \(httpResponse.statusCode)")
                requeueEvents(batch)
            } else {
                // Success -- remove persisted file if present
                try? FileManager.default.removeItem(at: persistenceURL)
            }
        } catch {
            logger.warning("Telemetry upload failed: \(error.localizedDescription)")
            requeueEvents(batch)
        }
    }

    /// Atomically drains the buffer and returns the events.
    private func drainBuffer() -> [InferenceTelemetryEvent] {
        lock.lock()
        let batch = buffer
        buffer.removeAll()
        lock.unlock()
        return batch
    }

    /// Re-inserts events at the front of the buffer after a failed upload.
    private func requeueEvents(_ events: [InferenceTelemetryEvent]) {
        lock.lock()
        buffer.insert(contentsOf: events, at: 0)
        lock.unlock()
    }

    private func startFlushTimer() {
        guard flushInterval > 0 else { return }
        let timer = DispatchSource.makeTimerSource(queue: timerQueue)
        timer.schedule(
            deadline: .now() + flushInterval,
            repeating: flushInterval
        )
        timer.setEventHandler { [weak self] in
            self?.flushAsync()
        }
        timer.resume()
        flushTimer = timer
    }

    private func restorePersistedEvents() {
        guard FileManager.default.fileExists(atPath: persistenceURL.path) else { return }
        do {
            let data = try Data(contentsOf: persistenceURL)
            let events = try JSONDecoder().decode([InferenceTelemetryEvent].self, from: data)
            lock.lock()
            buffer.insert(contentsOf: events, at: 0)
            lock.unlock()
            try? FileManager.default.removeItem(at: persistenceURL)
            logger.debug("Restored \(events.count) persisted telemetry events")
        } catch {
            logger.warning("Failed to restore persisted events: \(error.localizedDescription)")
        }
    }
}

// MARK: - Codable Payload

/// Batch payload sent to `POST /api/v1/telemetry/inference`.
struct TelemetryBatchPayload: Codable {
    let modelId: String
    let events: [InferenceTelemetryEvent]

    enum CodingKeys: String, CodingKey {
        case modelId = "model_id"
        case events
    }
}
