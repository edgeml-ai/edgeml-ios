import Foundation
import XCTest
@testable import EdgeML

final class DeviceAuthManagerTests: XCTestCase {
    override func setUp() {
        super.setUp()
        MockURLProtocol.responses = []
        MockURLProtocol.requests = []
    }

    override class func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    override class func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        super.tearDown()
    }

    func testBootstrapRefreshRevokeLifecycle() async throws {
        let manager = makeManager().manager
        let formatter = ISO8601DateFormatter.withFractional
        let exp = formatter.string(from: Date().addingTimeInterval(900))

        MockURLProtocol.responses = [
            .success(
                statusCode: 201,
                json: tokenPayload(access: "acc_bootstrap", refresh: "ref_bootstrap", expiresAt: exp)
            ),
            .success(
                statusCode: 200,
                json: tokenPayload(access: "acc_refresh", refresh: "ref_refresh", expiresAt: exp)
            ),
            .success(statusCode: 204, body: Data()),
        ]

        let bootstrapped = try await manager.bootstrap(bootstrapBearerToken: "bootstrap-token")
        XCTAssertEqual(bootstrapped.accessToken, "acc_bootstrap")

        let refreshed = try await manager.refresh()
        XCTAssertEqual(refreshed.accessToken, "acc_refresh")
        XCTAssertEqual(refreshed.refreshToken, "ref_refresh")

        try await manager.revoke()

        do {
            _ = try await manager.getAccessToken()
            XCTFail("Expected no token state after revoke")
        } catch {
            XCTAssertTrue(true)
        }
    }

    func testBootstrapSendsExpectedPayloadAndBearerToken() async throws {
        let fixture = makeManager()
        let manager = fixture.manager
        let formatter = ISO8601DateFormatter.withFractional
        let exp = formatter.string(from: Date().addingTimeInterval(900))

        MockURLProtocol.responses = [
            .success(
                statusCode: 201,
                json: tokenPayload(access: "acc_bootstrap", refresh: "ref_bootstrap", expiresAt: exp)
            ),
        ]

        _ = try await manager.bootstrap(
            bootstrapBearerToken: "bootstrap-token",
            scopes: ["devices:write", "heartbeat:write"],
            accessTTLSeconds: 600,
            deviceId: "device-db-id"
        )

        XCTAssertEqual(MockURLProtocol.requests.count, 1)
        let request = try XCTUnwrap(MockURLProtocol.requests.first)
        XCTAssertEqual(request.url?.path, "/api/v1/device-auth/bootstrap")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer bootstrap-token")
        let payload = try jsonBody(request)
        XCTAssertEqual(payload["org_id"] as? String, fixture.orgId)
        XCTAssertEqual(payload["device_identifier"] as? String, fixture.deviceIdentifier)
        XCTAssertEqual(payload["access_ttl_seconds"] as? Int, 600)
        XCTAssertEqual(payload["device_id"] as? String, "device-db-id")
        XCTAssertEqual(payload["scopes"] as? [String], ["devices:write", "heartbeat:write"])
    }

    func testRefreshUsesLatestRefreshTokenAfterRotation() async throws {
        let manager = makeManager().manager
        let formatter = ISO8601DateFormatter.withFractional
        let exp = formatter.string(from: Date().addingTimeInterval(900))

        MockURLProtocol.responses = [
            .success(
                statusCode: 201,
                json: tokenPayload(access: "acc_bootstrap", refresh: "ref_bootstrap", expiresAt: exp)
            ),
            .success(
                statusCode: 200,
                json: tokenPayload(access: "acc_refresh_1", refresh: "ref_refresh_1", expiresAt: exp)
            ),
            .success(
                statusCode: 200,
                json: tokenPayload(access: "acc_refresh_2", refresh: "ref_refresh_2", expiresAt: exp)
            ),
        ]

        _ = try await manager.bootstrap(bootstrapBearerToken: "bootstrap-token")
        _ = try await manager.refresh()
        _ = try await manager.refresh()

        XCTAssertEqual(MockURLProtocol.requests.count, 3)
        let firstRefreshPayload = try jsonBody(try XCTUnwrap(MockURLProtocol.requests[safe: 1]))
        let secondRefreshPayload = try jsonBody(try XCTUnwrap(MockURLProtocol.requests[safe: 2]))
        XCTAssertEqual(firstRefreshPayload["refresh_token"] as? String, "ref_bootstrap")
        XCTAssertEqual(secondRefreshPayload["refresh_token"] as? String, "ref_refresh_1")
    }

    func testGetAccessTokenFallsBackWhenRefreshFailsAndTokenStillValid() async throws {
        let manager = makeManager().manager
        let formatter = ISO8601DateFormatter.withFractional
        let exp = formatter.string(from: Date().addingTimeInterval(300))

        MockURLProtocol.responses = [
            .success(
                statusCode: 201,
                json: tokenPayload(access: "acc_bootstrap", refresh: "ref_bootstrap", expiresAt: exp)
            ),
            .failure(URLError(.notConnectedToInternet)),
        ]

        _ = try await manager.bootstrap(bootstrapBearerToken: "bootstrap-token")
        let token = try await manager.getAccessToken(refreshIfExpiringWithin: 600)
        XCTAssertEqual(token, "acc_bootstrap")
    }

    func testGetAccessTokenThrowsWhenExpiredAndRefreshFails() async throws {
        let manager = makeManager().manager
        let formatter = ISO8601DateFormatter.withFractional
        let expired = formatter.string(from: Date().addingTimeInterval(-60))

        MockURLProtocol.responses = [
            .success(
                statusCode: 201,
                json: tokenPayload(access: "acc_expired", refresh: "ref_expired", expiresAt: expired)
            ),
            .failure(URLError(.cannotConnectToHost)),
        ]

        _ = try await manager.bootstrap(bootstrapBearerToken: "bootstrap-token")

        do {
            _ = try await manager.getAccessToken(refreshIfExpiringWithin: 30)
            XCTFail("Expected refresh failure to surface for expired token")
        } catch {
            XCTAssertTrue(true)
        }
    }

    func testGetAccessTokenReturnsCurrentTokenWhenNotNearExpiry() async throws {
        let manager = makeManager().manager
        let formatter = ISO8601DateFormatter.withFractional
        let exp = formatter.string(from: Date().addingTimeInterval(3600))

        MockURLProtocol.responses = [
            .success(
                statusCode: 201,
                json: tokenPayload(access: "acc_bootstrap", refresh: "ref_bootstrap", expiresAt: exp)
            ),
        ]

        _ = try await manager.bootstrap(bootstrapBearerToken: "bootstrap-token")
        let token = try await manager.getAccessToken(refreshIfExpiringWithin: 30)
        XCTAssertEqual(token, "acc_bootstrap")
        XCTAssertEqual(MockURLProtocol.requests.count, 1)
    }

    func testRevokeFailurePreservesStoredState() async throws {
        let manager = makeManager().manager
        let formatter = ISO8601DateFormatter.withFractional
        let exp = formatter.string(from: Date().addingTimeInterval(600))

        MockURLProtocol.responses = [
            .success(
                statusCode: 201,
                json: tokenPayload(access: "acc_bootstrap", refresh: "ref_bootstrap", expiresAt: exp)
            ),
            .failure(URLError(.cannotConnectToHost)),
        ]

        _ = try await manager.bootstrap(bootstrapBearerToken: "bootstrap-token")

        do {
            try await manager.revoke()
            XCTFail("Expected revoke failure")
        } catch {
            XCTAssertTrue(true)
        }

        let token = try await manager.getAccessToken(refreshIfExpiringWithin: 30)
        XCTAssertEqual(token, "acc_bootstrap")
    }

    private func makeManager() -> (manager: DeviceAuthManager, orgId: String, deviceIdentifier: String) {
        let unique = UUID().uuidString
        let orgId = "org-\(unique)"
        let deviceIdentifier = "device-\(unique)"
        return (
            DeviceAuthManager(
            baseURL: URL(string: "https://api.example.com")!,
            orgId: orgId,
            deviceIdentifier: deviceIdentifier,
            keychainService: "ai.edgeml.tests.\(unique)"
            ),
            orgId,
            deviceIdentifier
        )
    }

    private func tokenPayload(access: String, refresh: String, expiresAt: String) -> [String: Any] {
        [
            "access_token": access,
            "refresh_token": refresh,
            "token_type": "Bearer",
            "expires_at": expiresAt,
            "org_id": "org-1",
            "device_identifier": "device-1",
            "scopes": ["devices:write"],
        ]
    }

    private func jsonBody(_ request: URLRequest) throws -> [String: Any] {
        let data = try XCTUnwrap(request.httpBody)
        let payload = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(payload as? [String: Any])
    }

}

private final class MockURLProtocol: URLProtocol {
    enum MockResponse {
        case success(statusCode: Int, json: [String: Any])
        case success(statusCode: Int, body: Data)
        case failure(Error)
    }

    static var responses: [MockResponse] = []
    static var requests: [URLRequest] = []

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.example.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        Self.requests.append(request)
        guard !Self.responses.isEmpty else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        let next = Self.responses.removeFirst()
        switch next {
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        case let .success(statusCode, json):
            do {
                let data = try JSONSerialization.data(withJSONObject: json)
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: statusCode,
                    httpVersion: nil,
                    headerFields: ["Content-Type": "application/json"]
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        case let .success(statusCode, body):
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

private extension ISO8601DateFormatter {
    static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}
