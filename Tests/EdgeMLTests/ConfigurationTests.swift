import XCTest
@testable import EdgeML

final class ConfigurationTests: XCTestCase {

    // MARK: - Default Configuration Tests

    func testDefaultConfiguration() {
        let config = EdgeMLConfiguration.standard

        XCTAssertEqual(config.maxRetryAttempts, 3)
        XCTAssertEqual(config.requestTimeout, 30)
        XCTAssertEqual(config.downloadTimeout, 300)
        XCTAssertFalse(config.enableLogging)
        XCTAssertEqual(config.logLevel, .info)
        XCTAssertEqual(config.maxCacheSize, 500 * 1024 * 1024)
        XCTAssertTrue(config.autoCheckUpdates)
        XCTAssertEqual(config.updateCheckInterval, 3600)
        XCTAssertFalse(config.requireWiFiForDownload)
        XCTAssertTrue(config.requireChargingForTraining)
        XCTAssertEqual(config.minimumBatteryLevel, 0.2)
    }

    func testDevelopmentConfiguration() {
        let config = EdgeMLConfiguration.development

        XCTAssertEqual(config.maxRetryAttempts, 1)
        XCTAssertTrue(config.enableLogging)
        XCTAssertEqual(config.logLevel, .debug)
        XCTAssertEqual(config.maxCacheSize, 1024 * 1024 * 1024)
        XCTAssertFalse(config.requireChargingForTraining)
    }

    func testProductionConfiguration() {
        let config = EdgeMLConfiguration.production

        XCTAssertEqual(config.maxRetryAttempts, 5)
        XCTAssertFalse(config.enableLogging)
        XCTAssertEqual(config.logLevel, .error)
        XCTAssertTrue(config.requireWiFiForDownload)
        XCTAssertTrue(config.requireChargingForTraining)
    }

    func testCustomConfiguration() {
        let config = EdgeMLConfiguration(
            network: .init(
                maxRetryAttempts: 5,
                requestTimeout: 60,
                downloadTimeout: 600,
                requireWiFiForDownload: true
            ),
            logging: .init(enableLogging: true, logLevel: .verbose),
            maxCacheSize: 100 * 1024 * 1024,
            autoCheckUpdates: false,
            updateCheckInterval: 7200,
            training: .init(requireChargingForTraining: false, minimumBatteryLevel: 0.5)
        )

        XCTAssertEqual(config.maxRetryAttempts, 5)
        XCTAssertEqual(config.requestTimeout, 60)
        XCTAssertEqual(config.downloadTimeout, 600)
        XCTAssertTrue(config.enableLogging)
        XCTAssertEqual(config.logLevel, .verbose)
        XCTAssertEqual(config.maxCacheSize, 100 * 1024 * 1024)
        XCTAssertFalse(config.autoCheckUpdates)
        XCTAssertEqual(config.updateCheckInterval, 7200)
        XCTAssertTrue(config.requireWiFiForDownload)
        XCTAssertFalse(config.requireChargingForTraining)
        XCTAssertEqual(config.minimumBatteryLevel, 0.5)
    }

    // MARK: - Background Constraints Tests

    func testDefaultBackgroundConstraints() {
        let constraints = BackgroundConstraints.standard

        XCTAssertTrue(constraints.requiresWiFi)
        XCTAssertTrue(constraints.requiresCharging)
        XCTAssertEqual(constraints.minimumBatteryLevel, 0.2)
        XCTAssertEqual(constraints.maxExecutionTime, 300)
    }

    func testRelaxedBackgroundConstraints() {
        let constraints = BackgroundConstraints.relaxed

        XCTAssertFalse(constraints.requiresWiFi)
        XCTAssertFalse(constraints.requiresCharging)
        XCTAssertEqual(constraints.minimumBatteryLevel, 0.1)
        XCTAssertEqual(constraints.maxExecutionTime, 600)
    }

    func testCustomBackgroundConstraints() {
        let constraints = BackgroundConstraints(
            requiresWiFi: false,
            requiresCharging: true,
            minimumBatteryLevel: 0.3,
            maxExecutionTime: 120
        )

        XCTAssertFalse(constraints.requiresWiFi)
        XCTAssertTrue(constraints.requiresCharging)
        XCTAssertEqual(constraints.minimumBatteryLevel, 0.3)
        XCTAssertEqual(constraints.maxExecutionTime, 120)
    }

    // MARK: - Log Level Tests

    func testLogLevelOrdering() {
        XCTAssertTrue(EdgeMLConfiguration.LogLevel.none.rawValue < EdgeMLConfiguration.LogLevel.error.rawValue)
        XCTAssertTrue(EdgeMLConfiguration.LogLevel.error.rawValue < EdgeMLConfiguration.LogLevel.warning.rawValue)
        XCTAssertTrue(EdgeMLConfiguration.LogLevel.warning.rawValue < EdgeMLConfiguration.LogLevel.info.rawValue)
        XCTAssertTrue(EdgeMLConfiguration.LogLevel.info.rawValue < EdgeMLConfiguration.LogLevel.debug.rawValue)
        XCTAssertTrue(EdgeMLConfiguration.LogLevel.debug.rawValue < EdgeMLConfiguration.LogLevel.verbose.rawValue)
    }

    // MARK: - Sub-Struct Tests

    func testNetworkPolicyDefaults() {
        let policy = EdgeMLConfiguration.NetworkPolicy()

        XCTAssertEqual(policy.maxRetryAttempts, 3)
        XCTAssertEqual(policy.requestTimeout, 30)
        XCTAssertEqual(policy.downloadTimeout, 300)
        XCTAssertFalse(policy.requireWiFiForDownload)
    }

    func testNetworkPolicyCustomValues() {
        let policy = EdgeMLConfiguration.NetworkPolicy(
            maxRetryAttempts: 10,
            requestTimeout: 120,
            downloadTimeout: 900,
            requireWiFiForDownload: true
        )

        XCTAssertEqual(policy.maxRetryAttempts, 10)
        XCTAssertEqual(policy.requestTimeout, 120)
        XCTAssertEqual(policy.downloadTimeout, 900)
        XCTAssertTrue(policy.requireWiFiForDownload)
    }

    func testLoggingPolicyDefaults() {
        let policy = EdgeMLConfiguration.LoggingPolicy()

        XCTAssertFalse(policy.enableLogging)
        XCTAssertEqual(policy.logLevel, .info)
    }

    func testLoggingPolicyCustomValues() {
        let policy = EdgeMLConfiguration.LoggingPolicy(
            enableLogging: true,
            logLevel: .verbose
        )

        XCTAssertTrue(policy.enableLogging)
        XCTAssertEqual(policy.logLevel, .verbose)
    }

    func testTrainingPolicyDefaults() {
        let policy = EdgeMLConfiguration.TrainingPolicy()

        XCTAssertTrue(policy.requireChargingForTraining)
        XCTAssertEqual(policy.minimumBatteryLevel, 0.2)
    }

    func testTrainingPolicyCustomValues() {
        let policy = EdgeMLConfiguration.TrainingPolicy(
            requireChargingForTraining: false,
            minimumBatteryLevel: 0.5
        )

        XCTAssertFalse(policy.requireChargingForTraining)
        XCTAssertEqual(policy.minimumBatteryLevel, 0.5)
    }

    // MARK: - Structured Init Tests

    func testStructuredInit() {
        let config = EdgeMLConfiguration(
            network: .init(maxRetryAttempts: 7, requestTimeout: 90, downloadTimeout: 450, requireWiFiForDownload: true),
            logging: .init(enableLogging: true, logLevel: .warning),
            maxCacheSize: 256 * 1024 * 1024,
            autoCheckUpdates: false,
            updateCheckInterval: 1800,
            training: .init(requireChargingForTraining: false, minimumBatteryLevel: 0.4),
            privacyConfiguration: .highPrivacy
        )

        XCTAssertEqual(config.network.maxRetryAttempts, 7)
        XCTAssertEqual(config.network.requestTimeout, 90)
        XCTAssertEqual(config.network.downloadTimeout, 450)
        XCTAssertTrue(config.network.requireWiFiForDownload)
        XCTAssertTrue(config.logging.enableLogging)
        XCTAssertEqual(config.logging.logLevel, .warning)
        XCTAssertEqual(config.maxCacheSize, 256 * 1024 * 1024)
        XCTAssertFalse(config.autoCheckUpdates)
        XCTAssertEqual(config.updateCheckInterval, 1800)
        XCTAssertFalse(config.training.requireChargingForTraining)
        XCTAssertEqual(config.training.minimumBatteryLevel, 0.4)
        XCTAssertTrue(config.privacyConfiguration.enableDifferentialPrivacy)
    }

    // MARK: - Backward-Compatible Accessor Tests

    func testBackwardCompatibleAccessorsMatchSubStructs() {
        let config = EdgeMLConfiguration(
            network: .init(maxRetryAttempts: 8, requestTimeout: 45, downloadTimeout: 500, requireWiFiForDownload: true),
            logging: .init(enableLogging: true, logLevel: .debug),
            training: .init(requireChargingForTraining: false, minimumBatteryLevel: 0.35)
        )

        XCTAssertEqual(config.maxRetryAttempts, config.network.maxRetryAttempts)
        XCTAssertEqual(config.requestTimeout, config.network.requestTimeout)
        XCTAssertEqual(config.downloadTimeout, config.network.downloadTimeout)
        XCTAssertEqual(config.requireWiFiForDownload, config.network.requireWiFiForDownload)
        XCTAssertEqual(config.enableLogging, config.logging.enableLogging)
        XCTAssertEqual(config.logLevel, config.logging.logLevel)
        XCTAssertEqual(config.requireChargingForTraining, config.training.requireChargingForTraining)
        XCTAssertEqual(config.minimumBatteryLevel, config.training.minimumBatteryLevel)
    }

    // MARK: - Structured Init Consistency

    func testStructuredInitBackwardAccessorsMatch() {
        let config = EdgeMLConfiguration(
            network: .init(maxRetryAttempts: 4, requestTimeout: 60, downloadTimeout: 400, requireWiFiForDownload: true),
            logging: .init(enableLogging: true, logLevel: .warning),
            maxCacheSize: 300 * 1024 * 1024,
            autoCheckUpdates: false,
            updateCheckInterval: 7200,
            training: .init(requireChargingForTraining: false, minimumBatteryLevel: 0.15)
        )

        XCTAssertEqual(config.maxRetryAttempts, 4)
        XCTAssertEqual(config.requestTimeout, 60)
        XCTAssertEqual(config.downloadTimeout, 400)
        XCTAssertTrue(config.enableLogging)
        XCTAssertEqual(config.logLevel, .warning)
        XCTAssertEqual(config.maxCacheSize, 300 * 1024 * 1024)
        XCTAssertFalse(config.autoCheckUpdates)
        XCTAssertEqual(config.updateCheckInterval, 7200)
        XCTAssertTrue(config.requireWiFiForDownload)
        XCTAssertFalse(config.requireChargingForTraining)
        XCTAssertEqual(config.minimumBatteryLevel, 0.15)
    }

    // MARK: - Preset Semantics

    func testDevelopmentIsMorePermissiveThanProduction() {
        let dev = EdgeMLConfiguration.development
        let prod = EdgeMLConfiguration.production

        XCTAssertLessThan(dev.maxRetryAttempts, prod.maxRetryAttempts)
        XCTAssertFalse(dev.requireWiFiForDownload)
        XCTAssertTrue(prod.requireWiFiForDownload)
        XCTAssertFalse(dev.requireChargingForTraining)
        XCTAssertTrue(prod.requireChargingForTraining)
        XCTAssertLessThan(dev.minimumBatteryLevel, prod.minimumBatteryLevel)
    }

    func testDevelopmentHasLoggingEnabled() {
        XCTAssertTrue(EdgeMLConfiguration.development.enableLogging)
        XCTAssertEqual(EdgeMLConfiguration.development.logLevel, .debug)
    }

    func testProductionHasLoggingDisabled() {
        XCTAssertFalse(EdgeMLConfiguration.production.enableLogging)
        XCTAssertEqual(EdgeMLConfiguration.production.logLevel, .error)
    }

    func testProductionChecksUpdatesLessFrequently() {
        let dev = EdgeMLConfiguration.development
        let prod = EdgeMLConfiguration.production

        XCTAssertGreaterThan(prod.updateCheckInterval, dev.updateCheckInterval)
    }

    func testProductionHasSmallerCache() {
        let dev = EdgeMLConfiguration.development
        let prod = EdgeMLConfiguration.production

        XCTAssertGreaterThan(dev.maxCacheSize, prod.maxCacheSize)
    }
}
