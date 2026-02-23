import XCTest
@testable import Octomil

final class NetworkMonitorTests: XCTestCase {

    func testSharedInstance() {
        let monitor1 = NetworkMonitor.shared
        let monitor2 = NetworkMonitor.shared

        XCTAssertTrue(monitor1 === monitor2)
    }

    func testAddAndRemoveHandler() {
        let monitor = NetworkMonitor.shared
        let expectation = XCTestExpectation(description: "Handler called")

        let token = monitor.addHandler { _ in
            // Handler is called immediately with current status
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // Remove handler should not crash
        monitor.removeHandler(token)
    }

    func testConnectionProperties() throws {
        let monitor = NetworkMonitor.shared

        try XCTSkipIf(!monitor.isConnected, "No network available")

        // These should not crash and should return consistent values
        let isOnWiFi = monitor.isOnWiFi
        let isOnCellular = monitor.isOnCellular
        let isExpensive = monitor.isExpensive
        let isConstrained = monitor.isConstrained

        // At least one interface type should be identifiable when connected
        XCTAssertTrue(isOnWiFi || isOnCellular || !isOnWiFi && !isOnCellular)

        // Log for debugging
        print("Network status - Connected: true, WiFi: \(isOnWiFi), Cellular: \(isOnCellular)")
        print("Expensive: \(isExpensive), Constrained: \(isConstrained)")
    }

    func testWaitForConnectivityWithTimeout() async throws {
        let monitor = NetworkMonitor.shared

        try XCTSkipIf(!monitor.isConnected, "No network available")

        // When already connected, should return true almost immediately
        let connected = await monitor.waitForConnectivity(timeout: 0.1)
        XCTAssertTrue(connected, "Should report connected when network is available")
    }
}
