import XCTest
@testable import EdgeML

final class PrivacyConfigurationTests: XCTestCase {

    // MARK: - Preset Tests

    func testStandardPreset() {
        let config = PrivacyConfiguration.standard

        XCTAssertTrue(config.enableStaggeredUpdates)
        XCTAssertEqual(config.minUploadDelaySeconds, 0)
        XCTAssertEqual(config.maxUploadDelaySeconds, 300)
        XCTAssertFalse(config.enableDifferentialPrivacy)
        XCTAssertEqual(config.dpEpsilon, 1.0)
        XCTAssertEqual(config.dpClippingNorm, 1.0)
    }

    func testHighPrivacyPreset() {
        let config = PrivacyConfiguration.highPrivacy

        XCTAssertTrue(config.enableStaggeredUpdates)
        XCTAssertEqual(config.minUploadDelaySeconds, 60)
        XCTAssertEqual(config.maxUploadDelaySeconds, 600)
        XCTAssertTrue(config.enableDifferentialPrivacy)
        XCTAssertEqual(config.dpEpsilon, 0.5)
        XCTAssertEqual(config.dpClippingNorm, 1.0)
    }

    func testDisabledPreset() {
        let config = PrivacyConfiguration.disabled

        XCTAssertFalse(config.enableStaggeredUpdates)
        XCTAssertEqual(config.minUploadDelaySeconds, 0)
        XCTAssertEqual(config.maxUploadDelaySeconds, 0)
        XCTAssertFalse(config.enableDifferentialPrivacy)
    }

    // MARK: - Custom Configuration Tests

    func testCustomConfiguration() {
        let config = PrivacyConfiguration(
            enableStaggeredUpdates: false,
            minUploadDelaySeconds: 10,
            maxUploadDelaySeconds: 120,
            enableDifferentialPrivacy: true,
            dpEpsilon: 0.1,
            dpClippingNorm: 2.0
        )

        XCTAssertFalse(config.enableStaggeredUpdates)
        XCTAssertEqual(config.minUploadDelaySeconds, 10)
        XCTAssertEqual(config.maxUploadDelaySeconds, 120)
        XCTAssertTrue(config.enableDifferentialPrivacy)
        XCTAssertEqual(config.dpEpsilon, 0.1)
        XCTAssertEqual(config.dpClippingNorm, 2.0)
    }

    // MARK: - Upload Delay Tests

    func testRandomUploadDelayReturnsZeroWhenStaggeredUpdatesDisabled() {
        let config = PrivacyConfiguration.disabled

        for _ in 0..<100 {
            XCTAssertEqual(config.randomUploadDelay(), 0.0)
        }
    }

    func testRandomUploadDelayWithinBounds() {
        let config = PrivacyConfiguration(
            enableStaggeredUpdates: true,
            minUploadDelaySeconds: 10,
            maxUploadDelaySeconds: 60
        )

        for _ in 0..<100 {
            let delay = config.randomUploadDelay()
            XCTAssertGreaterThanOrEqual(delay, 10.0)
            XCTAssertLessThanOrEqual(delay, 60.0)
        }
    }

    func testRandomUploadDelayWithZeroMinimum() {
        let config = PrivacyConfiguration.standard

        for _ in 0..<100 {
            let delay = config.randomUploadDelay()
            XCTAssertGreaterThanOrEqual(delay, 0.0)
            XCTAssertLessThanOrEqual(delay, 300.0)
        }
    }

    func testRandomUploadDelayWithEqualMinMax() {
        let config = PrivacyConfiguration(
            enableStaggeredUpdates: true,
            minUploadDelaySeconds: 42,
            maxUploadDelaySeconds: 42
        )

        let delay = config.randomUploadDelay()
        XCTAssertEqual(delay, 42.0)
    }

    // MARK: - Privacy Budget Semantics

    func testHighPrivacyHasSmallerEpsilonThanStandard() {
        // Smaller epsilon = more private (more noise)
        XCTAssertLessThan(
            PrivacyConfiguration.highPrivacy.dpEpsilon,
            PrivacyConfiguration.standard.dpEpsilon
        )
    }

    func testHighPrivacyHasLongerMinimumDelay() {
        XCTAssertGreaterThan(
            PrivacyConfiguration.highPrivacy.minUploadDelaySeconds,
            PrivacyConfiguration.standard.minUploadDelaySeconds
        )
    }
}
