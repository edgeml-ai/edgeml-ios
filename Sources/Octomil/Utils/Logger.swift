import Foundation
import os

/// Logger for the Octomil SDK.
public struct OctomilLogger: Sendable {

    // MARK: - Shared Instance

    /// Shared logger instance.
    public static let shared = OctomilLogger()

    // MARK: - Properties

    private let logger: Logger
    private let isEnabled: Bool

    // MARK: - Initialization

    private init() {
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "Octomil")
        self.isEnabled = true
    }

    /// Creates a logger with custom configuration.
    /// - Parameters:
    ///   - subsystem: The subsystem identifier.
    ///   - category: The category for this logger.
    public init(subsystem: String = "ai.octomil.sdk", category: String) {
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

public func octomilLog(_ message: String, level: OctomilLogLevel = .info) {
    switch level {
    case .debug:
        OctomilLogger.shared.debug(message)
    case .info:
        OctomilLogger.shared.info(message)
    case .warning:
        OctomilLogger.shared.warning(message)
    case .error:
        OctomilLogger.shared.error(message)
    }
}

/// Log levels for Octomil logging.
public enum OctomilLogLevel: Sendable {
    case debug
    case info
    case warning
    case error
}
