import Foundation
import os

/// Logger for the EdgeML SDK.
public struct EdgeMLLogger: Sendable {

    // MARK: - Shared Instance

    /// Shared logger instance.
    public static let shared = EdgeMLLogger()

    // MARK: - Properties

    private let logger: Logger
    private let isEnabled: Bool

    // MARK: - Initialization

    private init() {
        self.logger = Logger(subsystem: "ai.edgeml.sdk", category: "EdgeML")
        self.isEnabled = true
    }

    /// Creates a logger with custom configuration.
    /// - Parameters:
    ///   - subsystem: The subsystem identifier.
    ///   - category: The category for this logger.
    public init(subsystem: String = "ai.edgeml.sdk", category: String) {
        self.logger = Logger(subsystem: subsystem, category: category)
        self.isEnabled = true
    }

    // MARK: - Logging Methods

    /// Logs a debug message.
    /// - Parameter message: The message to log.
    public func debug(_ message: String) {
        guard isEnabled else { return }
        logger.debug("\(message)")
    }

    /// Logs an info message.
    /// - Parameter message: The message to log.
    public func info(_ message: String) {
        guard isEnabled else { return }
        logger.info("\(message)")
    }

    /// Logs a warning message.
    /// - Parameter message: The message to log.
    public func warning(_ message: String) {
        guard isEnabled else { return }
        logger.warning("\(message)")
    }

    /// Logs an error message.
    /// - Parameter message: The message to log.
    public func error(_ message: String) {
        guard isEnabled else { return }
        logger.error("\(message)")
    }

    /// Logs a critical error message.
    /// - Parameter message: The message to log.
    public func critical(_ message: String) {
        guard isEnabled else { return }
        logger.critical("\(message)")
    }
}

// MARK: - Convenience Functions

/// Global logging functions for convenience.

public func edgeMLLog(_ message: String, level: EdgeMLLogLevel = .info) {
    switch level {
    case .debug:
        EdgeMLLogger.shared.debug(message)
    case .info:
        EdgeMLLogger.shared.info(message)
    case .warning:
        EdgeMLLogger.shared.warning(message)
    case .error:
        EdgeMLLogger.shared.error(message)
    }
}

/// Log levels for EdgeML logging.
public enum EdgeMLLogLevel: Sendable {
    case debug
    case info
    case warning
    case error
}
