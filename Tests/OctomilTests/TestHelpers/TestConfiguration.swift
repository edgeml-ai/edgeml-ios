@testable import Octomil

/// Factory for ``OctomilConfiguration`` instances tuned for fast unit tests.
enum TestConfiguration {

    /// A configuration with aggressive timeouts suitable for unit tests.
    static func fast(
        maxRetryAttempts: Int = 0,
        requestTimeout: Double = 2,
        downloadTimeout: Double = 5,
        enableLogging: Bool = false,
        maxCacheSize: UInt64 = 10 * 1024 * 1024 // 10 MB
    ) -> OctomilConfiguration {
        OctomilConfiguration(
            network: .init(
                maxRetryAttempts: maxRetryAttempts,
                requestTimeout: requestTimeout,
                downloadTimeout: downloadTimeout,
                requireWiFiForDownload: false
            ),
            logging: .init(enableLogging: enableLogging),
            maxCacheSize: maxCacheSize,
            autoCheckUpdates: false,
            updateCheckInterval: 1,
            training: .init(
                requireChargingForTraining: false,
                minimumBatteryLevel: 0.0
            )
        )
    }

    /// Shorthand for the standard fast configuration.
    static var standard: OctomilConfiguration { fast() }
}
