import Foundation

// MARK: - Personalization

extension EdgeMLClient {

    /// Gets personalized model state from the server.
    ///
    /// - Parameter deviceId: Device ID (defaults to this device's ID).
    /// - Returns: Personalized model response.
    /// - Throws: `EdgeMLError` if the request fails.
    public func getPersonalizedModel(deviceId: String? = nil) async throws -> PersonalizedModelResponse {
        let resolvedDeviceId = deviceId ?? self.deviceId
        guard let id = resolvedDeviceId else {
            throw EdgeMLError.deviceNotRegistered
        }

        return try await apiClient.getPersonalizedModel(deviceId: id)
    }

    /// Uploads a personalized model update to the server.
    ///
    /// - Parameters:
    ///   - deviceId: Device ID (defaults to this device's ID).
    ///   - modelId: Model identifier.
    ///   - weightsData: Personalized weight data.
    ///   - metrics: Training metrics.
    ///   - strategy: Personalization strategy used (e.g., "ditto", "fedper").
    /// - Throws: `EdgeMLError` if the upload fails.
    public func uploadPersonalizedUpdate(
        deviceId: String? = nil,
        modelId: String,
        weightsData: Data,
        metrics: [String: Double],
        strategy: String? = nil
    ) async throws {
        let resolvedDeviceId = deviceId ?? self.deviceId
        guard let id = resolvedDeviceId else {
            throw EdgeMLError.deviceNotRegistered
        }

        let request = PersonalizedUpdateRequest(
            deviceId: id,
            modelId: modelId,
            weightsData: weightsData,
            metrics: metrics,
            strategy: strategy
        )

        try await apiClient.uploadPersonalizedUpdate(request)

        if configuration.enableLogging {
            logger.info("Uploaded personalized update for model: \(modelId)")
        }
    }
}
