import Foundation
import os.log

// MARK: - Model Operations

extension APIClient {

    /// Gets the resolved version for a device and model.
    /// - Parameters:
    ///   - deviceId: Device identifier.
    ///   - modelId: Model identifier.
    /// - Returns: Version resolution response.
    public func resolveVersion(deviceId: String, modelId: String) async throws -> VersionResolutionResponse {
        let path = "api/v1/devices/\(deviceId)/models/\(modelId)/version"
        var components = URLComponents(
            url: serverURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
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
    public func getDownloadURL(
        modelId: String,
        version: String,
        format: String = "coreml"
    ) async throws -> DownloadURLResponse {
        let path = "api/v1/models/\(modelId)/versions/\(version)/download-url"
        var components = URLComponents(
            url: serverURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
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
        let path = "api/v1/models/\(modelId)/updates"
        var components = URLComponents(
            url: serverURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
        )!
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
}

// MARK: - Training Operations

extension APIClient {

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

    /// Checks for a round assignment for this device.
    /// - Parameters:
    ///   - deviceId: Server-assigned device UUID.
    ///   - modelId: Model ID to check for assignments.
    /// - Returns: Round assignment if one is available, nil otherwise.
    public func checkRoundAssignment(deviceId: String, modelId: String) async throws -> RoundAssignment? {
        var components = URLComponents(
            url: serverURL.appendingPathComponent("api/v1/training/rounds"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [
            URLQueryItem(name: "device_id", value: deviceId),
            URLQueryItem(name: "model_id", value: modelId)
        ]

        var urlRequest = URLRequest(url: components.url!)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        do {
            let response: RoundAssignmentResponse = try await performRequest(urlRequest)
            return response.assignment
        } catch EdgeMLError.serverError(let statusCode, _) where statusCode == 404 {
            return nil
        }
    }

    /// Gets personalized model state for a device.
    /// - Parameter deviceId: Server-assigned device UUID.
    /// - Returns: Personalized model response.
    public func getPersonalizedModel(deviceId: String) async throws -> PersonalizedModelResponse {
        let url = serverURL.appendingPathComponent("api/v1/training/personalized/\(deviceId)")

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "GET"
        try configureHeaders(&urlRequest)

        return try await performRequest(urlRequest)
    }

    /// Uploads a personalized model update for a device.
    /// - Parameter request: Personalized update request.
    public func uploadPersonalizedUpdate(_ request: PersonalizedUpdateRequest) async throws {
        let url = serverURL.appendingPathComponent(
            "api/v1/training/personalized/\(request.deviceId)"
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(request)

        let _: EmptyResponse = try await performRequest(urlRequest)
    }
}

// MARK: - Events & Inference

extension APIClient {

    /// Tracks an event on the server.
    /// - Parameters:
    ///   - experimentId: Experiment identifier.
    ///   - event: Event to track.
    public func trackEvent(experimentId: String, event: TrackingEvent) async throws {
        let url = serverURL.appendingPathComponent(
            "api/v1/experiments/\(experimentId)/events"
        )

        var urlRequest = URLRequest(url: url)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
        try configureHeaders(&urlRequest)
        urlRequest.httpBody = try jsonEncoder.encode(event)

        let _: EmptyResponse = try await performRequest(urlRequest)
    }

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
}

// MARK: - Download

extension APIClient {

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
                    throw EdgeMLError.downloadFailed(
                        reason: "HTTP \(httpResponse.statusCode)"
                    )
                }

                return data
            } catch let error as EdgeMLError {
                throw error
            } catch {
                lastError = error
                retries += 1
                if retries < configuration.maxRetryAttempts {
                    // Exponential backoff
                    let delay = UInt64(pow(2.0, Double(retries)) * 1_000_000_000)
                    try await Task.sleep(nanoseconds: delay)
                }
            }
        }

        throw EdgeMLError.downloadFailed(
            reason: lastError?.localizedDescription ?? "Unknown error"
        )
    }
}
