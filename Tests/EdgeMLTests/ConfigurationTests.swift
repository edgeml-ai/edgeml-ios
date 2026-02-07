import XCTest
@testable import EdgeML

final class ConfigurationTests: XCTestCase {

    // MARK: - Default Configuration Tests

    func testDefaultConfiguration() {
        let config = EdgeMLConfiguration.default

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
            maxRetryAttempts: 5,
            requestTimeout: 60,
            downloadTimeout: 600,
            enableLogging: true,
            logLevel: .verbose,
            maxCacheSize: 100 * 1024 * 1024,
            autoCheckUpdates: false,
            updateCheckInterval: 7200,
            requireWiFiForDownload: true,
            requireChargingForTraining: false,
            minimumBatteryLevel: 0.5
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
        let constraints = BackgroundConstraints.default

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
}
