import XCTest
@testable import EdgeML

final class BonjourAdvertiserTests: XCTestCase {

    // MARK: - Initialization

    func testInitWithCustomDeviceName() {
        let advertiser = BonjourAdvertiser(deviceId: "dev_123", deviceName: "My Test iPhone")

        // Should not be advertising immediately after init
        XCTAssertFalse(advertiser.isAdvertising)

        // Verify TXT record contains the custom name
        let txt = advertiser.buildTXTRecord()
        XCTAssertEqual(txt["device_name"], "My Test iPhone")
        XCTAssertEqual(txt["device_id"], "dev_123")
    }

    func testInitWithDefaultDeviceName() {
        let advertiser = BonjourAdvertiser(deviceId: "dev_456")

        XCTAssertFalse(advertiser.isAdvertising)

        // Default name should be non-empty (UIDevice.current.name or Host name)
        let txt = advertiser.buildTXTRecord()
        let name = txt["device_name"]
        XCTAssertNotNil(name)
        XCTAssertFalse(name!.isEmpty, "Default device name should not be empty")
    }

    // MARK: - Start / Stop State

    func testStartAdvertisingSetsIsAdvertisingTrue() throws {
        let advertiser = BonjourAdvertiser(deviceId: "dev_start")

        try advertiser.startAdvertising()

        XCTAssertTrue(advertiser.isAdvertising)

        // Cleanup
        advertiser.stopAdvertising()
    }

    func testStopAdvertisingSetsIsAdvertisingFalse() throws {
        let advertiser = BonjourAdvertiser(deviceId: "dev_stop")

        try advertiser.startAdvertising()
        XCTAssertTrue(advertiser.isAdvertising)

        advertiser.stopAdvertising()
        XCTAssertFalse(advertiser.isAdvertising)
    }

    func testStopWhenNotStartedIsNoOp() {
        let advertiser = BonjourAdvertiser(deviceId: "dev_noop")

        // Should not crash or change state
        advertiser.stopAdvertising()
        XCTAssertFalse(advertiser.isAdvertising)
    }

    func testDoubleStartIsIdempotent() throws {
        let advertiser = BonjourAdvertiser(deviceId: "dev_double")

        try advertiser.startAdvertising()
        XCTAssertTrue(advertiser.isAdvertising)

        // Second start should be a no-op (no crash, still advertising)
        try advertiser.startAdvertising()
        XCTAssertTrue(advertiser.isAdvertising)

        // Cleanup
        advertiser.stopAdvertising()
    }

    func testDoubleStopIsIdempotent() throws {
        let advertiser = BonjourAdvertiser(deviceId: "dev_dblstop")

        try advertiser.startAdvertising()
        advertiser.stopAdvertising()
        XCTAssertFalse(advertiser.isAdvertising)

        // Second stop should be a no-op
        advertiser.stopAdvertising()
        XCTAssertFalse(advertiser.isAdvertising)
    }

    // MARK: - TXT Record

    func testTXTRecordContainsExpectedKeys() {
        let advertiser = BonjourAdvertiser(deviceId: "dev_txt", deviceName: "Test Device")

        let txt = advertiser.buildTXTRecord()

        XCTAssertEqual(txt["device_id"], "dev_txt")
        XCTAssertEqual(txt["device_name"], "Test Device")

        let platform = txt["platform"]
        XCTAssertNotNil(platform)

        // Platform should be ios or macos depending on test runner
        #if os(iOS)
        XCTAssertEqual(platform, "ios")
        #elseif os(macOS)
        XCTAssertEqual(platform, "macos")
        #endif
    }

    func testTXTRecordPlatformValue() {
        // Validate the static helper directly
        let platform = BonjourAdvertiser.currentPlatform()

        #if os(iOS)
        XCTAssertEqual(platform, "ios")
        #elseif os(macOS)
        XCTAssertEqual(platform, "macos")
        #endif
    }

    // MARK: - Service Type

    func testServiceTypeConstant() {
        XCTAssertEqual(BonjourAdvertiser.serviceType, "_edgeml._tcp")
    }

    // MARK: - Start with explicit port

    func testStartWithExplicitPort() throws {
        let advertiser = BonjourAdvertiser(deviceId: "dev_port")

        // Use an ephemeral port (0 lets the OS pick)
        try advertiser.startAdvertising(port: 0)
        XCTAssertTrue(advertiser.isAdvertising)

        advertiser.stopAdvertising()
        XCTAssertFalse(advertiser.isAdvertising)
    }
}

// MARK: - DiscoveryManager Tests

final class DiscoveryManagerTests: XCTestCase {

    func testInitialStateIsNotDiscoverable() {
        let manager = DiscoveryManager()
        XCTAssertFalse(manager.isDiscoverable)
    }

    func testStartDiscoverableMakesDeviceDiscoverable() {
        let manager = DiscoveryManager()

        manager.startDiscoverable(deviceId: "dev_mgr_start")

        XCTAssertTrue(manager.isDiscoverable)

        // Cleanup
        manager.stopDiscoverable()
    }

    func testStopDiscoverableMakesDeviceNotDiscoverable() {
        let manager = DiscoveryManager()

        manager.startDiscoverable(deviceId: "dev_mgr_stop")
        XCTAssertTrue(manager.isDiscoverable)

        manager.stopDiscoverable()
        XCTAssertFalse(manager.isDiscoverable)
    }

    func testStopWhenNotDiscoverableIsNoOp() {
        let manager = DiscoveryManager()

        // Should not crash
        manager.stopDiscoverable()
        XCTAssertFalse(manager.isDiscoverable)
    }

    func testDoubleStartIsIdempotent() {
        let manager = DiscoveryManager()

        manager.startDiscoverable(deviceId: "dev_mgr_dbl")
        XCTAssertTrue(manager.isDiscoverable)

        // Second call should be a no-op
        manager.startDiscoverable(deviceId: "dev_mgr_dbl")
        XCTAssertTrue(manager.isDiscoverable)

        manager.stopDiscoverable()
    }

    func testStartStopStartCycle() {
        let manager = DiscoveryManager()

        manager.startDiscoverable(deviceId: "dev_mgr_cycle")
        XCTAssertTrue(manager.isDiscoverable)

        manager.stopDiscoverable()
        XCTAssertFalse(manager.isDiscoverable)

        // Re-start should work
        manager.startDiscoverable(deviceId: "dev_mgr_cycle2")
        XCTAssertTrue(manager.isDiscoverable)

        manager.stopDiscoverable()
        XCTAssertFalse(manager.isDiscoverable)
    }

    func testStartWithCustomDeviceName() {
        let manager = DiscoveryManager()

        manager.startDiscoverable(deviceId: "dev_mgr_name", deviceName: "Custom Name")
        XCTAssertTrue(manager.isDiscoverable)

        manager.stopDiscoverable()
    }
}
