import Foundation
import Network
import os.log

/// Monitors network connectivity for the EdgeML SDK.
public final class NetworkMonitor: @unchecked Sendable {

    // MARK: - Shared Instance

    /// Shared network monitor instance.
    public static let shared = NetworkMonitor()

    // MARK: - Properties

    private let monitor: NWPathMonitor
    private let queue: DispatchQueue
    private let logger: Logger

    private var currentPath: NWPath?
    private var handlers: [UUID: (Bool) -> Void] = [:]
    private let lock = NSLock()

    /// Whether the network is currently available.
    public var isConnected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentPath?.status == .satisfied
    }

    /// Whether the device is connected via WiFi.
    public var isOnWiFi: Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentPath?.usesInterfaceType(.wifi) == true
    }

    /// Whether the device is connected via cellular.
    public var isOnCellular: Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentPath?.usesInterfaceType(.cellular) == true
    }

    /// Whether the connection is expensive (metered).
    public var isExpensive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentPath?.isExpensive == true
    }

    /// Whether the connection is constrained (Low Data Mode).
    public var isConstrained: Bool {
        lock.lock()
        defer { lock.unlock() }
        return currentPath?.isConstrained == true
    }

    // MARK: - Initialization

    private init() {
        self.monitor = NWPathMonitor()
        self.queue = DispatchQueue(label: "ai.edgeml.networkmonitor")
        self.logger = Logger(subsystem: "ai.edgeml.sdk", category: "NetworkMonitor")

        setupMonitor()
    }

    // MARK: - Setup

    private func setupMonitor() {
        monitor.pathUpdateHandler = { [weak self] path in
            guard let self = self else { return }

            self.lock.lock()
            self.currentPath = path
            let handlers = self.handlers
            self.lock.unlock()

            let isConnected = path.status == .satisfied

            self.logger.debug("Network status changed: \(isConnected ? "connected" : "disconnected")")

            for (_, handler) in handlers {
                handler(isConnected)
            }
        }

        monitor.start(queue: queue)
    }

    // MARK: - Observation

    /// Adds a handler for network status changes.
    /// - Parameter handler: Closure called when network status changes.
    /// - Returns: Token to use for removing the handler.
    @discardableResult
    public func addHandler(_ handler: @escaping (Bool) -> Void) -> UUID {
        let token = UUID()

        lock.lock()
        handlers[token] = handler
        lock.unlock()

        // Immediately call with current status
        if let path = currentPath {
            handler(path.status == .satisfied)
        }

        return token
    }

    /// Removes a handler.
    /// - Parameter token: Token returned from `addHandler`.
    public func removeHandler(_ token: UUID) {
        lock.lock()
        handlers.removeValue(forKey: token)
        lock.unlock()
    }

    // MARK: - Waiting

    /// Waits for network connectivity.
    /// - Parameter timeout: Maximum time to wait.
    /// - Returns: Whether network became available within timeout.
    public func waitForConnectivity(timeout: TimeInterval) async -> Bool {
        if isConnected {
            return true
        }

        let resumeTracker = ResumeTracker()

        return await withCheckedContinuation { continuation in
            let token = UUID()

            // Set up timeout
            let timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                self.removeHandler(token)

                if await resumeTracker.tryResume() {
                    continuation.resume(returning: false)
                }
            }

            // Add handler
            lock.lock()
            handlers[token] = { [weak self] isConnected in
                guard let self = self else { return }

                if isConnected {
                    Task {
                        if await resumeTracker.tryResume() {
                            timeoutTask.cancel()
                            self.removeHandler(token)
                            continuation.resume(returning: true)
                        }
                    }
                }
            }
            lock.unlock()
        }
    }
}

/// Actor to safely track whether a continuation has already been resumed.
private actor ResumeTracker {
    private var didResume = false

    /// Attempts to mark as resumed. Returns `true` if this is the first call, `false` otherwise.
    func tryResume() -> Bool {
        guard !didResume else { return false }
        didResume = true
        return true
    }
}
