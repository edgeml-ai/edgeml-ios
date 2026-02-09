import XCTest
@testable import EdgeML

final class EdgeMLClientTests: XCTestCase {

    private static let testHost = "api.example.com"
    private static let testServerURL = URL(string: "https://\(testHost)")!

    // MARK: - Initialization Tests

    func testClientInitialization() {
        let client = EdgeMLClient(
            deviceAccessToken: "test-device-token",
            orgId: "org-test",
            serverURL: Self.testServerURL
        )

        XCTAssertNotNil(client)
        XCTAssertFalse(client.isRegistered)
        XCTAssertNil(client.deviceId)
    }

    func testClientInitializationWithConfiguration() {
        let config = EdgeMLConfiguration(
            maxRetryAttempts: 5,
            requestTimeout: 60,
            enableLogging: true
        )

        let client = EdgeMLClient(
            deviceAccessToken: "test-device-token",
            orgId: "org-test",
            serverURL: Self.testServerURL,
            configuration: config
        )

        XCTAssertNotNil(client)
    }

    func testSharedInstance() {
        let client = EdgeMLClient(
            deviceAccessToken: "test-device-token",
            orgId: "org-test",
            serverURL: Self.testServerURL
        )

        // The last created client becomes the shared instance
        XCTAssertNotNil(EdgeMLClient.shared)
        XCTAssertTrue(client === EdgeMLClient.shared)
    }

    // MARK: - Registration Tests

    func testRegistrationRequiredForModelDownload() async {
        let client = EdgeMLClient(
            deviceAccessToken: "test-device-token",
            orgId: "org-test",
            serverURL: Self.testServerURL
        )

        XCTAssertFalse(client.isRegistered)

        do {
            _ = try await client.downloadModel(modelId: "test-model")
            XCTFail("Should throw deviceNotRegistered error")
        } catch let error as EdgeMLError {
            if case .deviceNotRegistered = error {
                // Expected
            } else {
                XCTFail("Wrong error type: \(error)")
            }
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    // MARK: - Cache Tests

    func testGetCachedModelReturnsNil() {
        let client = EdgeMLClient(
            deviceAccessToken: "test-device-token",
            orgId: "org-test",
            serverURL: Self.testServerURL
        )

        let model = client.getCachedModel(modelId: "nonexistent-model")
        XCTAssertNil(model)
    }

    func testGetCachedModelWithVersionReturnsNil() {
        let client = EdgeMLClient(
            deviceAccessToken: "test-device-token",
            orgId: "org-test",
            serverURL: Self.testServerURL
        )

        let model = client.getCachedModel(modelId: "nonexistent-model", version: "1.0.0")
        XCTAssertNil(model)
    }

    // MARK: - Server URL Tests

    func testDefaultServerHost() {
        XCTAssertEqual(EdgeMLClient.defaultServerHost, "api.edgeml.ai")
    }

    func testDefaultServerURL() {
        let url = EdgeMLClient.defaultServerURL
        XCTAssertEqual(url.scheme, "https")
        XCTAssertEqual(url.host, "api.edgeml.ai")
    }

    func testClientUsesDefaultServerURLWhenNotSpecified() {
        let client = EdgeMLClient(
            deviceAccessToken: "test-device-token",
            orgId: "org-test"
        )

        XCTAssertNotNil(client)
    }

    func testClientUsesCustomServerURL() {
        let client = EdgeMLClient(
            deviceAccessToken: "test-device-token",
            orgId: "org-test",
            serverURL: Self.testServerURL
        )

        XCTAssertNotNil(client)
    }

    // MARK: - Device ID Tests

    func testCurrentDeviceIdNilBeforeRegistration() {
        let client = EdgeMLClient(
            deviceAccessToken: "test-device-token",
            orgId: "org-test",
            serverURL: Self.testServerURL
        )

        XCTAssertNil(client.deviceId)
    }

    func testDeviceIdentifierNilBeforeRegistration() {
        let client = EdgeMLClient(
            deviceAccessToken: "test-device-token",
            orgId: "org-test",
            serverURL: Self.testServerURL
        )

        XCTAssertNil(client.deviceIdentifier)
    }

    // MARK: - Org ID Tests

    func testOrgIdIsStored() {
        let client = EdgeMLClient(
            deviceAccessToken: "test-device-token",
            orgId: "my-org-123",
            serverURL: Self.testServerURL
        )

        XCTAssertEqual(client.orgId, "my-org-123")
    }

    // MARK: - Background Training Tests

    func testBackgroundTrainingConfiguration() {
        let client = EdgeMLClient(
            deviceAccessToken: "test-device-token",
            orgId: "org-test",
            serverURL: Self.testServerURL
        )

        // This should not crash
        client.enableBackgroundTraining(
            modelId: "test-model",
            dataProvider: { MockBatchProvider() },
            constraints: .relaxed
        )

        // Disable should also not crash
        client.disableBackgroundTraining()
    }
}

// MARK: - Mock Batch Provider

class MockBatchProvider: MLBatchProvider {
    var count: Int { return 0 }

    func features(at _: Int) -> MLFeatureProvider {
        fatalError("Not implemented for tests")
    }
}
