import Foundation
import os.log

/// HTTP client for communicating with the EdgeML server API.
public actor APIClient {

    // MARK: - API Paths

    static let defaultVersionAlias = "latest"

    // MARK: - Properties

    let serverURL: URL
    let configuration: EdgeMLConfiguration
    let session: URLSession
    let jsonDecoder: JSONDecoder
    let jsonEncoder: JSONEncoder
    let logger: Logger

    private var deviceToken: String?

    // MARK: - Initialization

    /// Creates a new API client.
    /// - Parameters:
    ///   - serverURL: The base URL of the EdgeML server.
    ///   - configuration: SDK configuration.
    public init(
        serverURL: URL,
        configuration: EdgeMLConfiguration
    ) {
        self.serverURL = serverURL
        self.configuration = configuration
        self.logger = Logger(subsystem: "ai.edgeml.sdk", category: "APIClient")

        // Configure URL session
        let sessionConfig = URLSessionConfiguration.default
        sessionConfig.timeoutIntervalForRequest = configuration.requestTimeout
        sessionConfig.timeoutIntervalForResource = configuration.downloadTimeout
        sessionConfig.waitsForConnectivity = true
        self.session = URLSession(configuration: sessionConfig)

        // Configure JSON decoder
        self.jsonDecoder = JSONDecoder()
        self.jsonDecoder.dateDecodingStrategy = .iso8601

        // Configure JSON encoder
        self.jsonEncoder = JSONEncoder()
        self.jsonEncoder.dateEncodingStrategy = .iso8601
    }

    // MARK: - Token Management

    /// Sets the short-lived device access token for authenticated requests.
    public func setDeviceToken(_ token: String) {
        self.deviceToken = token
    }

    /// Gets the current device token.
    public func getDeviceToken() -> String? {
        return deviceToken
    }
}

// MARK: - Device Operations

extension APIClient {

    /// Registers a device with the server.
    /// - Parameter request: Registration request.
    /// - Returns: Registration response with server-assigned ID.
    public func registerDevice(
        _ request: DeviceRegistrationRequest
    ) async throws -> DeviceRegistrationResponse {
        let url = serverURL.appendingPathComponent("api/v1/devices/register")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(request)

        return try await performRequest(urlRequest)
    }

    /// Sends a heartbeat to the server to indicate device is alive.
    /// - Parameters:
    ///   - deviceId: Server-assigned device UUID.
    ///   - request: Heartbeat request with optional status update.
    /// - Returns: Heartbeat response with updated status.
    public func sendHeartbeat(
        deviceId: String,
        request: HeartbeatRequest = HeartbeatRequest()
    ) async throws -> HeartbeatResponse {
        let url = serverURL.appendingPathComponent(
            "api/v1/devices/\(deviceId)/heartbeat"
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(request)

        return try await performRequest(urlRequest)
    }

    /// Gets the groups this device belongs to.
    /// - Parameter deviceId: Server-assigned device UUID.
    /// - Returns: List of device groups.
    public func getDeviceGroups(deviceId: String) async throws -> [DeviceGroup] {
        let url = serverURL.appendingPathComponent(
            "api/v1/devices/\(deviceId)/groups"
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        let response: DeviceGroupsResponse = try await performRequest(urlRequest)
        return response.groups
    }

    /// Gets device information from server.
    /// - Parameter deviceId: Server-assigned device UUID.
    /// - Returns: Full device information.
    public func getDeviceInfo(deviceId: String) async throws -> DeviceInfo {
        let url = serverURL.appendingPathComponent("api/v1/devices/\(deviceId)")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }
}

// MARK: - Internal Helpers

extension APIClient {

    func configureHeaders(_ request: inout URLRequest) throws {
        guard let bearer = deviceToken, !bearer.isEmpty else {
            throw EdgeMLError.authenticationFailed(
                reason: "Missing device access token"
            )
        }
        request.setValue(
            "Bearer \(bearer)",
            forHTTPHeaderField: "Authorization"
        )
        request.setValue("edgeml-ios/1.0", forHTTPHeaderField: "User-Agent")
    }

    func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        if configuration.enableLogging {
            let method = request.httpMethod ?? "GET"
            let url = request.url?.absoluteString ?? ""
            logger.debug("Request: \(method) \(url)")
        }

        var retries = 0
        var lastError: Error?

        while retries < configuration.maxRetryAttempts {
            do {
                let (data, response) = try await session.data(for: request)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw EdgeMLError.unknown(underlying: nil)
                }

                if configuration.enableLogging {
                    logger.debug("Response: \(httpResponse.statusCode)")
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    throw mapHTTPError(
                        statusCode: httpResponse.statusCode, data: data
                    )
                }

                return try decodeResponse(data)

            } catch let error as EdgeMLError {
                throw error
            } catch let error as URLError {
                throw mapURLError(error)
            } catch {
                lastError = error
                retries += 1
                if retries < configuration.maxRetryAttempts {
                    let delay = UInt64(
                        pow(2.0, Double(retries)) * 1_000_000_000
                    )
                    try await Task.sleep(nanoseconds: delay)
                }
            }
        }

        throw EdgeMLError.unknown(underlying: lastError)
    }

    private func mapHTTPError(statusCode: Int, data: Data) -> EdgeMLError {
        let errorMessage = parseErrorMessage(from: data) ?? "Unknown error"

        switch statusCode {
        case 401:
            return EdgeMLError.invalidAPIKey
        case 403:
            return EdgeMLError.authenticationFailed(reason: errorMessage)
        default:
            return EdgeMLError.serverError(
                statusCode: statusCode, message: errorMessage
            )
        }
    }

    private func mapURLError(_ error: URLError) -> EdgeMLError {
        switch error.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return EdgeMLError.networkUnavailable
        case .timedOut:
            return EdgeMLError.requestTimeout
        case .cancelled:
            return EdgeMLError.cancelled
        default:
            return EdgeMLError.unknown(underlying: error)
        }
    }

    private func decodeResponse<T: Decodable>(_ data: Data) throws -> T {
        // Handle empty responses
        if T.self == EmptyResponse.self,
           data.isEmpty || data == Data("null".utf8),
           let emptyResponse = EmptyResponse() as? T {
            return emptyResponse
        }

        do {
            return try jsonDecoder.decode(T.self, from: data)
        } catch {
            throw EdgeMLError.decodingError(
                underlying: error.localizedDescription
            )
        }
    }

    private func parseErrorMessage(from data: Data) -> String? {
        if let errorResponse = try? jsonDecoder.decode(
            APIErrorResponse.self, from: data
        ) {
            return errorResponse.detail
        }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Empty Response

struct EmptyResponse: Decodable {}
