import Foundation
import os.log

/// HTTP client for communicating with the EdgeML server API.
public actor APIClient {

    // MARK: - API Paths

    private static let defaultVersionAlias = "latest"

    // MARK: - Properties

    private let serverURL: URL
    private let configuration: EdgeMLConfiguration
    private let session: URLSession
    private let jsonDecoder: JSONDecoder
    private let jsonEncoder: JSONEncoder
    private let logger: Logger

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

    /// Creates an API client with an injected URL session configuration (for testing).
    internal init(
        serverURL: URL,
        configuration: EdgeMLConfiguration,
        sessionConfiguration: URLSessionConfiguration
    ) {
        self.serverURL = serverURL
        self.configuration = configuration
        self.logger = Logger(subsystem: "ai.edgeml.sdk", category: "APIClient")

        sessionConfiguration.timeoutIntervalForRequest = configuration.requestTimeout
        sessionConfiguration.timeoutIntervalForResource = configuration.downloadTimeout
        self.session = URLSession(configuration: sessionConfiguration)

        self.jsonDecoder = JSONDecoder()
        self.jsonDecoder.dateDecodingStrategy = .iso8601

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

    // MARK: - Device Registration

    /// Registers a device with the server.
    /// - Parameter request: Registration request.
    /// - Returns: Registration response with server-assigned ID.
    public func registerDevice(_ request: DeviceRegistrationRequest) async throws -> DeviceRegistrationResponse {
        let url = serverURL.appendingPathComponent("api/v1/devices/register")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(request)

        return try await performRequest(urlRequest)
    }

    // MARK: - Device Heartbeat

    /// Sends a heartbeat to the server to indicate device is alive.
    /// - Parameters:
    ///   - deviceId: Server-assigned device UUID.
    ///   - request: Heartbeat request with optional status update.
    /// - Returns: Heartbeat response with updated status.
    public func sendHeartbeat(deviceId: String, request: HeartbeatRequest = HeartbeatRequest()) async throws -> HeartbeatResponse {
        let url = serverURL.appendingPathComponent("api/v1/devices/\(deviceId)/heartbeat")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(request)

        return try await performRequest(urlRequest)
    }

    // MARK: - Device Groups

    /// Gets the groups this device belongs to.
    /// - Parameter deviceId: Server-assigned device UUID.
    /// - Returns: List of device groups.
    public func getDeviceGroups(deviceId: String) async throws -> [DeviceGroup] {
        let url = serverURL.appendingPathComponent("api/v1/devices/\(deviceId)/groups")

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

    // MARK: - Model Operations

    /// Gets the resolved version for a device and model.
    /// - Parameters:
    ///   - deviceId: Device identifier.
    ///   - modelId: Model identifier.
    /// - Returns: Version resolution response.
    public func resolveVersion(deviceId: String, modelId: String) async throws -> VersionResolutionResponse {
        var components = URLComponents(url: serverURL.appendingPathComponent("api/v1/devices/\(deviceId)/models/\(modelId)/version"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "include_bucket", value: "true")
        ]

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }

    /// Gets model metadata.
    /// - Parameters:
    ///   - modelId: Model identifier.
    ///   - version: Optional specific version.
    /// - Returns: Model metadata.
    public func getModelMetadata(modelId: String, version: String? = nil) async throws -> ModelMetadata {
        var path = "api/v1/models/\(modelId)/versions"
        if let version = version {
            path += "/\(version)"
        } else {
            path += "/\(Self.defaultVersionAlias)"
        }

        var urlRequest = URLRequest(url: serverURL.appendingPathComponent(path))
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        let response: ModelVersionResponse = try await performRequest(urlRequest)
        return ModelMetadata(
            modelId: response.modelId,
            version: response.version,
            checksum: response.checksum,
            fileSize: response.sizeBytes,
            createdAt: response.createdAt,
            format: response.format,
            supportsTraining: true,
            description: response.description,
            inputSchema: nil,
            outputSchema: nil
        )
    }

    /// Gets a pre-signed download URL for a model.
    /// - Parameters:
    ///   - modelId: Model identifier.
    ///   - version: Model version.
    ///   - format: Model format (default: coreml).
    /// - Returns: Download URL response.
    public func getDownloadURL(modelId: String, version: String, format: String = "coreml") async throws -> DownloadURLResponse {
        var components = URLComponents(url: serverURL.appendingPathComponent("api/v1/models/\(modelId)/versions/\(version)/download-url"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "format", value: format)
        ]

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }

    /// Checks for model updates.
    /// - Parameters:
    ///   - modelId: Model identifier.
    ///   - currentVersion: Current version on device.
    /// - Returns: Update info if available, nil otherwise.
    public func checkForUpdates(modelId: String, currentVersion: String) async throws -> ModelUpdateInfo? {
        var components = URLComponents(url: serverURL.appendingPathComponent("api/v1/models/\(modelId)/updates"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "current_version", value: currentVersion)
        ]

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        do {
            return try await performRequest(urlRequest)
        } catch EdgeMLError.serverError(let statusCode, _) where statusCode == 404 {
            // No update available
            return nil
        }
    }

    // MARK: - Training Operations

    /// Uploads weight updates to the server.
    /// - Parameter update: Weight update to upload.
    public func uploadWeights(_ update: WeightUpdate) async throws {
        let url = serverURL.appendingPathComponent("api/v1/training/weights")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(update)

        let _: EmptyResponse = try await performRequest(urlRequest)
    }

    /// Tracks an event on the server.
    /// - Parameters:
    ///   - experimentId: Experiment identifier.
    ///   - event: Event to track.
    public func trackEvent(experimentId: String, event: TrackingEvent) async throws {
        let url = serverURL.appendingPathComponent("api/v1/experiments/\(experimentId)/events")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(event)

        let _: EmptyResponse = try await performRequest(urlRequest)
    }

    // MARK: - Inference Events

    /// Reports a streaming inference event to the server.
    /// - Parameter request: Inference event request.
    public func reportInferenceEvent(_ request: InferenceEventRequest) async throws {
        let url = serverURL.appendingPathComponent("api/v1/inference/events")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(request)

        let _: EmptyResponse = try await performRequest(urlRequest)
    }

    // MARK: - Secure Aggregation

    /// Joins a SecAgg session for a training round.
    /// - Parameters:
    ///   - deviceId: Server-assigned device UUID.
    ///   - roundId: The training round to join.
    /// - Returns: Session details including this client's index.
    public func joinSecAggSession(deviceId: String, roundId: String) async throws -> SecAggSessionResponse {
        let url = serverURL.appendingPathComponent("api/v1/secagg/sessions/join")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)

        let body: [String: String] = ["device_id": deviceId, "round_id": roundId]
        urlRequest.httpBody = try jsonEncoder.encode(body)

        return try await performRequest(urlRequest)
    }

    /// Submits key shares for SecAgg Phase 1.
    /// - Parameter request: Share keys request.
    public func submitSecAggShares(_ request: SecAggShareKeysRequest) async throws {
        let url = serverURL.appendingPathComponent("api/v1/secagg/shares")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(request)

        let _: EmptyResponse = try await performRequest(urlRequest)
    }

    /// Submits masked model update for SecAgg Phase 2.
    /// - Parameter request: Masked input request.
    public func submitSecAggMaskedInput(_ request: SecAggMaskedInputRequest) async throws {
        let url = serverURL.appendingPathComponent("api/v1/secagg/masked-input")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(request)

        let _: EmptyResponse = try await performRequest(urlRequest)
    }

    /// Requests unmasking info and submits this client's unmasking shares.
    /// - Parameters:
    ///   - sessionId: SecAgg session identifier.
    ///   - deviceId: Server-assigned device UUID.
    /// - Returns: Unmask response with dropped client indices.
    public func getSecAggUnmaskInfo(sessionId: String, deviceId: String) async throws -> SecAggUnmaskResponse {
        var components = URLComponents(url: serverURL.appendingPathComponent("api/v1/secagg/unmask"), resolvingAgainstBaseURL: false)!
        components.queryItems = [
            URLQueryItem(name: "session_id", value: sessionId),
            URLQueryItem(name: "device_id", value: deviceId)
        ]

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }

    /// Submits unmasking data for SecAgg Phase 3.
    /// - Parameter request: Unmask request.
    public func submitSecAggUnmask(_ request: SecAggUnmaskRequest) async throws {
        let url = serverURL.appendingPathComponent("api/v1/secagg/unmask")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(request)

        let _: EmptyResponse = try await performRequest(urlRequest)
    }

    // MARK: - Download

    /// Downloads data from a URL.
    /// - Parameter url: URL to download from.
    /// - Returns: Downloaded data.
    public func downloadData(from url: URL) async throws -> Data {
        if configuration.enableLogging {
            logger.debug("Downloading from: \(url.absoluteString)")
        }

        var retries = 0
        var lastError: Error?

        while retries < configuration.maxRetryAttempts {
            do {
                let (data, response) = try await session.data(from: url)

                guard let httpResponse = response as? HTTPURLResponse else {
                    throw EdgeMLError.unknown(underlying: nil)
                }

                guard (200...299).contains(httpResponse.statusCode) else {
                    throw EdgeMLError.downloadFailed(reason: "HTTP \(httpResponse.statusCode)")
                }

                return data
            } catch let error as EdgeMLError {
                throw error
            } catch {
                lastError = error
                retries += 1
                if retries < configuration.maxRetryAttempts {
                    // Exponential backoff
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retries)) * 1_000_000_000))
                }
            }
        }

        throw EdgeMLError.downloadFailed(reason: lastError?.localizedDescription ?? "Unknown error")
    }

    // MARK: - Private Methods

    private func configureHeaders(_ request: inout URLRequest) throws {
        guard let bearer = deviceToken, !bearer.isEmpty else {
            throw EdgeMLError.authenticationFailed(reason: "Missing device access token")
        }
        request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization")
        request.setValue("edgeml-ios/1.0", forHTTPHeaderField: "User-Agent")
    }

    // swiftlint:disable:next cyclomatic_complexity
    private func performRequest<T: Decodable>(_ request: URLRequest) async throws -> T {
        if configuration.enableLogging {
            logger.debug("Request: \(request.httpMethod ?? "GET") \(request.url?.absoluteString ?? "")")
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
                    let errorMessage = parseErrorMessage(from: data) ?? "Unknown error"

                    switch httpResponse.statusCode {
                    case 401:
                        throw EdgeMLError.invalidAPIKey
                    case 403:
                        throw EdgeMLError.authenticationFailed(reason: errorMessage)
                    case 404:
                        throw EdgeMLError.serverError(statusCode: 404, message: errorMessage)
                    default:
                        throw EdgeMLError.serverError(statusCode: httpResponse.statusCode, message: errorMessage)
                    }
                }

                // Handle empty responses
                if T.self == EmptyResponse.self, data.isEmpty || data == Data("null".utf8) {
                    guard let emptyResult = EmptyResponse() as? T else {
                        throw EdgeMLError.decodingError(underlying: "Failed to cast EmptyResponse")
                    }
                    return emptyResult
                }

                do {
                    return try jsonDecoder.decode(T.self, from: data)
                } catch {
                    throw EdgeMLError.decodingError(underlying: error.localizedDescription)
                }

            } catch let error as EdgeMLError {
                // Don't retry EdgeML errors
                throw error
            } catch let error as URLError {
                switch error.code {
                case .notConnectedToInternet, .networkConnectionLost:
                    throw EdgeMLError.networkUnavailable
                case .timedOut:
                    throw EdgeMLError.requestTimeout
                case .cancelled:
                    throw EdgeMLError.cancelled
                default:
                    lastError = error
                    retries += 1
                    if retries < configuration.maxRetryAttempts {
                        try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retries)) * 1_000_000_000))
                    }
                }
            } catch {
                lastError = error
                retries += 1
                if retries < configuration.maxRetryAttempts {
                    try await Task.sleep(nanoseconds: UInt64(pow(2.0, Double(retries)) * 1_000_000_000))
                }
            }
        }

        throw EdgeMLError.unknown(underlying: lastError)
    }

    private func parseErrorMessage(from data: Data) -> String? {
        if let errorResponse = try? jsonDecoder.decode(APIErrorResponse.self, from: data) {
            return errorResponse.detail
        }
        return String(data: data, encoding: .utf8)
    }
}

// MARK: - Empty Response

private struct EmptyResponse: Decodable {}
