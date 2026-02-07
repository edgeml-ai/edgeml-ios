import Foundation
import XCTest
@testable import EdgeML

final class DeviceAuthManagerTests: XCTestCase {

    override class func setUp() {
        super.setUp()
        URLProtocol.registerClass(MockURLProtocol.self)
    }

    override class func tearDown() {
        URLProtocol.unregisterClass(MockURLProtocol.self)
        super.tearDown()
    }

    func testBootstrapRefreshRevokeLifecycle() async throws {
        let manager = makeManager()
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

    func testGetAccessTokenFallsBackWhenRefreshFailsAndTokenStillValid() async throws {
        let manager = makeManager()
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
        let manager = makeManager()
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

    private func makeManager() -> DeviceAuthManager {
        let unique = UUID().uuidString
        return DeviceAuthManager(
            baseURL: URL(string: "https://api.example.com")!,
            orgId: "org-\(unique)",
            deviceIdentifier: "device-\(unique)",
            keychainService: "ai.edgeml.tests.\(unique)"
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
}

private final class MockURLProtocol: URLProtocol {
    enum MockResponse {
        case success(statusCode: Int, json: [String: Any])
        case success(statusCode: Int, body: Data)
        case failure(Error)
    }

    static var responses: [MockResponse] = []

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.example.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
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

private extension ISO8601DateFormatter {
    static let withFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
}

