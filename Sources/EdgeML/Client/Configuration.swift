import Foundation

/// Configuration options for the EdgeML SDK.
public struct EdgeMLConfiguration: Sendable {

    // MARK: - Properties

    /// Maximum number of retry attempts for failed requests.
    public let maxRetryAttempts: Int

    /// Timeout interval for API requests in seconds.
    public let requestTimeout: TimeInterval

    /// Timeout interval for model downloads in seconds.
    public let downloadTimeout: TimeInterval

    /// Whether to enable debug logging.
    public let enableLogging: Bool

    /// Log level for SDK operations.
    public let logLevel: LogLevel

    /// Maximum size of the model cache in bytes.
    public let maxCacheSize: UInt64

    /// Whether to automatically check for model updates.
    public let autoCheckUpdates: Bool

    /// Interval for checking model updates in seconds.
    public let updateCheckInterval: TimeInterval

    /// Whether to require WiFi for model downloads.
    public let requireWiFiForDownload: Bool

    /// Whether to require charging for background training.
    public let requireChargingForTraining: Bool

    /// Minimum battery level required for background training (0.0 - 1.0).
    public let minimumBatteryLevel: Float

    /// Privacy configuration for upload behavior and differential privacy.
    public let privacyConfiguration: PrivacyConfiguration

    // MARK: - Log Level

    /// Log levels for SDK operations.
    public enum LogLevel: Int, Sendable {
        case none = 0
        case error = 1
        case warning = 2
        case info = 3
        case debug = 4
        case verbose = 5
    }

    // MARK: - Initialization

    /// Creates a new configuration with the specified options.
    /// - Parameters:
    ///   - maxRetryAttempts: Maximum number of retry attempts for failed requests.
    ///   - requestTimeout: Timeout interval for API requests in seconds.
    ///   - downloadTimeout: Timeout interval for model downloads in seconds.
    ///   - enableLogging: Whether to enable debug logging.
    ///   - logLevel: Log level for SDK operations.
    ///   - maxCacheSize: Maximum size of the model cache in bytes.
    ///   - autoCheckUpdates: Whether to automatically check for model updates.
    ///   - updateCheckInterval: Interval for checking model updates in seconds.
    ///   - requireWiFiForDownload: Whether to require WiFi for model downloads.
    ///   - requireChargingForTraining: Whether to require charging for background training.
    ///   - minimumBatteryLevel: Minimum battery level required for background training.
    ///   - privacyConfiguration: Privacy configuration for uploads and differential privacy.
    public init(
        maxRetryAttempts: Int = 3,
        requestTimeout: TimeInterval = 30,
        downloadTimeout: TimeInterval = 300,
        enableLogging: Bool = false,
        logLevel: LogLevel = .info,
        maxCacheSize: UInt64 = 500 * 1024 * 1024, // 500 MB
        autoCheckUpdates: Bool = true,
        updateCheckInterval: TimeInterval = 3600, // 1 hour
        requireWiFiForDownload: Bool = false,
        requireChargingForTraining: Bool = true,
        minimumBatteryLevel: Float = 0.2,
        privacyConfiguration: PrivacyConfiguration = .default
    ) {
        self.maxRetryAttempts = maxRetryAttempts
        self.requestTimeout = requestTimeout
        self.downloadTimeout = downloadTimeout
        self.enableLogging = enableLogging
        self.logLevel = logLevel
        self.maxCacheSize = maxCacheSize
        self.autoCheckUpdates = autoCheckUpdates
        self.updateCheckInterval = updateCheckInterval
        self.requireWiFiForDownload = requireWiFiForDownload
        self.requireChargingForTraining = requireChargingForTraining
        self.minimumBatteryLevel = minimumBatteryLevel
        self.privacyConfiguration = privacyConfiguration
    }

    // MARK: - Presets

    /// Default configuration suitable for most use cases.
    public static let `default` = EdgeMLConfiguration()

    /// Configuration optimized for development and testing.
    public static let development = EdgeMLConfiguration(
        maxRetryAttempts: 1,
        requestTimeout: 60,
        downloadTimeout: 600,
        enableLogging: true,
        logLevel: .debug,
        maxCacheSize: 1024 * 1024 * 1024, // 1 GB
        autoCheckUpdates: true,
        updateCheckInterval: 300, // 5 minutes
        requireWiFiForDownload: false,
        requireChargingForTraining: false,
        minimumBatteryLevel: 0.1
    )

    /// Configuration optimized for production with conservative settings.
    public static let production = EdgeMLConfiguration(
        maxRetryAttempts: 5,
        requestTimeout: 30,
        downloadTimeout: 300,
        enableLogging: false,
        logLevel: .error,
        maxCacheSize: 200 * 1024 * 1024, // 200 MB
        autoCheckUpdates: true,
        updateCheckInterval: 86400, // 24 hours
        requireWiFiForDownload: true,
        requireChargingForTraining: true,
        minimumBatteryLevel: 0.3
    )
}

// MARK: - Background Constraints

/// Constraints for background training operations.
public struct BackgroundConstraints: Sendable {

    /// Whether WiFi connection is required.
    public let requiresWiFi: Bool

    /// Whether device must be charging.
    public let requiresCharging: Bool

    /// Minimum battery level (0.0 - 1.0).
    public let minimumBatteryLevel: Float

    /// Maximum time allowed for the background task in seconds.
    public let maxExecutionTime: TimeInterval

    /// Creates new background constraints.
    /// - Parameters:
    ///   - requiresWiFi: Whether WiFi connection is required.
    ///   - requiresCharging: Whether device must be charging.
    ///   - minimumBatteryLevel: Minimum battery level (0.0 - 1.0).
    ///   - maxExecutionTime: Maximum time allowed for the background task.
    public init(
        requiresWiFi: Bool = true,
        requiresCharging: Bool = true,
        minimumBatteryLevel: Float = 0.2,
        maxExecutionTime: TimeInterval = 300
    ) {
        self.requiresWiFi = requiresWiFi
        self.requiresCharging = requiresCharging
        self.minimumBatteryLevel = minimumBatteryLevel
        self.maxExecutionTime = maxExecutionTime
    }

    /// Default constraints suitable for most use cases.
    public static let `default` = BackgroundConstraints()

    /// Relaxed constraints for development.
    public static let relaxed = BackgroundConstraints(
        requiresWiFi: false,
        requiresCharging: false,
        minimumBatteryLevel: 0.1,
        maxExecutionTime: 600
    )
}
