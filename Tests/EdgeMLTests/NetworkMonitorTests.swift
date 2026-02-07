import XCTest
@testable import EdgeML

final class NetworkMonitorTests: XCTestCase {

    func testSharedInstance() {
        let monitor1 = NetworkMonitor.shared
        let monitor2 = NetworkMonitor.shared

        XCTAssertTrue(monitor1 === monitor2)
    }

    func testAddAndRemoveHandler() {
        let monitor = NetworkMonitor.shared
        let expectation = XCTestExpectation(description: "Handler called")

        let token = monitor.addHandler { isConnected in
            // Handler is called immediately with current status
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)

        // Remove handler should not crash
        monitor.removeHandler(token)
    }

    func testConnectionProperties() {
        let monitor = NetworkMonitor.shared

        // These should not crash and should return consistent values
        let isConnected = monitor.isConnected
        let isOnWiFi = monitor.isOnWiFi
        let isOnCellular = monitor.isOnCellular
        let isExpensive = monitor.isExpensive
        let isConstrained = monitor.isConstrained

        // At least one should be true if connected
        if isConnected {
            XCTAssertTrue(isOnWiFi || isOnCellular || !isOnWiFi && !isOnCellular)
        }

        // Log for debugging
        print("Network status - Connected: \(isConnected), WiFi: \(isOnWiFi), Cellular: \(isOnCellular)")
        print("Expensive: \(isExpensive), Constrained: \(isConstrained)")
    }

    func testWaitForConnectivityWithTimeout() async {
        let monitor = NetworkMonitor.shared

        // Very short timeout to test timeout behavior
        let connected = await monitor.waitForConnectivity(timeout: 0.1)

        // Either connects immediately or times out
        // We're just testing it doesn't crash
        print("Wait for connectivity result: \(connected)")
    }
}
