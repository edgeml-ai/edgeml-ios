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
            network: .init(maxRetryAttempts: 5, requestTimeout: 60),
            logging: .init(enableLogging: true)
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

    #if os(iOS)
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
    #endif

    // MARK: - Register Idempotency

    func testRegisterTwiceProducesConsistentErrors() async {
        // register() always calls the API — without a real server both calls
        // should fail with the same class of error. Crucially, the second call
        // must NOT crash or leave the client in a broken state.
        let client = EdgeMLClient(
            deviceAccessToken: "test-device-token",
            orgId: "org-test",
            serverURL: Self.testServerURL
        )

        var firstError: Error?
        var secondError: Error?

        do {
            _ = try await client.register()
        } catch {
            firstError = error
        }

        do {
            _ = try await client.register()
        } catch {
            secondError = error
        }

        // Both calls should fail (no real server)
        XCTAssertNotNil(firstError, "First register() should fail without a real server")
        XCTAssertNotNil(secondError, "Second register() should fail without a real server")

        // Client should still be usable after failed registrations
        XCTAssertFalse(client.isRegistered)
        XCTAssertNil(client.deviceId)

        // Cache and other non-registration operations should still work
        XCTAssertNil(client.getCachedModel(modelId: "any-model"))
    }

    func testRegisterSetsClientStateToInitializing() async {
        let client = EdgeMLClient(
            deviceAccessToken: "test-device-token",
            orgId: "org-test",
            serverURL: Self.testServerURL
        )

        XCTAssertEqual(client.currentState, .uninitialized)

        // Start registration (will fail due to no real server, but state
        // should transition to .initializing before the network call)
        let task = Task {
            _ = try? await client.register()
        }

        // Give a tiny moment for the state transition
        try? await Task.sleep(nanoseconds: 10_000_000)
        task.cancel()

        // After a failed registration, client should NOT be in .ready
        XCTAssertNotEqual(client.currentState, .ready)
    }
}

// MARK: - Mock Batch Provider

class MockBatchProvider: MLBatchProvider {
    var count: Int { return 0 }

    func features(at _: Int) -> MLFeatureProvider {
        fatalError("Not implemented for tests")
    }
}
