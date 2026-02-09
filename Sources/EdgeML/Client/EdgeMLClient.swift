import Foundation
import CoreML
import os.log
#if canImport(UIKit)
import UIKit
#endif

/// Main entry point for the EdgeML SDK.
///
/// `EdgeMLClient` provides a high-level API for:
/// - Device registration
/// - Model download and caching
/// - On-device inference
/// - Federated training participation
/// - Background task scheduling
///
/// # Example Usage
///
/// ```swift
/// let client = EdgeMLClient(
///     deviceAccessToken: "<short-lived-device-token>",
///     orgId: "org_123",
///     serverURL: URL(string: "https://api.edgeml.ai")!
/// )
///
/// // Register device
/// let registration = try await client.register()
///
/// // Download model
/// let model = try await client.downloadModel(modelId: "fraud_detection")
///
/// // Run inference
/// let prediction = try model.predict(input: inputFeatures)
/// ```
public final class EdgeMLClient: @unchecked Sendable {

    // MARK: - Constants

    /// Default EdgeML server host.
    public static let defaultServerHost = "api.edgeml.ai"

    /// Default EdgeML server URL.
    public static let defaultServerURL = URL(string: "https://\(defaultServerHost)")!

    // MARK: - Shared Instance

    /// Shared instance for background operations.
    public private(set) static var shared: EdgeMLClient?

    // MARK: - Properties

    private let apiClient: APIClient
    private let modelManager: ModelManager
    private let secureStorage: SecureStorage
    private let configuration: EdgeMLConfiguration
    private let logger: Logger

    /// Organization ID for this client.
    public let orgId: String

    /// Server-assigned device UUID (set after registration).
    private var serverDeviceId: String?
    /// Client-generated device identifier (e.g., IDFV).
    private var clientDeviceIdentifier: String?
    private var deviceRegistration: DeviceRegistrationResponse?

    /// Heartbeat timer for automatic health reporting.
    private var heartbeatTask: Task<Void, Never>?
    private let heartbeatInterval: TimeInterval

    /// Whether the device is registered with the server.
    public var isRegistered: Bool {
        return deviceRegistration != nil
    }

    /// The server-assigned device ID (UUID).
    public var deviceId: String? {
        return serverDeviceId ?? deviceRegistration?.id
    }

    /// The client-generated device identifier.
    public var deviceIdentifier: String? {
        return clientDeviceIdentifier ?? deviceRegistration?.deviceIdentifier
    }

    // MARK: - Initialization

    /// Creates a new EdgeML client.
    /// - Parameters:
    ///   - deviceAccessToken: Short-lived device access token from backend bootstrap flow.
    ///   - orgId: Organization identifier.
    ///   - serverURL: Base URL of the EdgeML server.
    ///   - configuration: SDK configuration options.
    ///   - heartbeatInterval: Interval for automatic heartbeats (default: 5 minutes).
    public init(
        deviceAccessToken: String,
        orgId: String,
        serverURL: URL = EdgeMLClient.defaultServerURL,
        configuration: EdgeMLConfiguration = .standard,
        heartbeatInterval: TimeInterval = 300
    ) {
        self.orgId = orgId
        self.configuration = configuration
        self.heartbeatInterval = heartbeatInterval
        self.logger = Logger(subsystem: "ai.edgeml.sdk", category: "EdgeMLClient")

        self.secureStorage = SecureStorage()
        self.apiClient = APIClient(
            serverURL: serverURL,
            configuration: configuration
        )

        self.modelManager = ModelManager(
            apiClient: apiClient,
            configuration: configuration
        )

        // Store device token securely
        try? secureStorage.storeDeviceToken(deviceAccessToken)
        Task {
            await apiClient.setDeviceToken(deviceAccessToken)
        }

        // Try to restore device token from keychain
        if let storedToken = try? secureStorage.getDeviceToken() {
            Task {
                await apiClient.setDeviceToken(storedToken)
            }
        }

        // Try to restore server device ID from keychain
        if let storedId = try? secureStorage.getServerDeviceId() {
            self.serverDeviceId = storedId
        }

        // Set as shared instance
        EdgeMLClient.shared = self
    }

    deinit {
        heartbeatTask?.cancel()
    }

    // MARK: - Device Registration

    /// Registers this device with the EdgeML server.
    ///
    /// Registration establishes this device's identity and enables
    /// participation in federated learning rounds.
    ///
    /// - Parameters:
    ///   - deviceIdentifier: Client-generated device ID (e.g., IDFV). If nil, auto-generated.
    ///   - appVersion: Host application version.
    ///   - metadata: Optional additional metadata.
    /// - Returns: Registration information including server-assigned ID.
    /// - Throws: `EdgeMLError` if registration fails.
    public func register(
        deviceIdentifier: String? = nil,
        appVersion: String? = nil,
        metadata: [String: String]? = nil
    ) async throws -> DeviceRegistrationResponse {
        if configuration.enableLogging {
            logger.info("Registering device...")
        }

        // Generate or use provided device identifier
        let identifier = deviceIdentifier ?? generateDeviceIdentifier()
        self.clientDeviceIdentifier = identifier

        let deviceInfo = await buildDeviceInfo()

        let capabilities = DeviceCapabilities(
            supportsTraining: deviceInfo.supportsTraining,
            coremlVersion: deviceInfo.coremlVersion,
            hasNeuralEngine: deviceInfo.hasNeuralEngine,
            maxBatchSize: 32,
            supportedFormats: ["coreml", "onnx"]
        )

        let hardwareInfo = DeviceInfoRequest(
            manufacturer: "Apple",
            model: deviceInfo.deviceModel,
            cpuArchitecture: "arm64",
            gpuAvailable: deviceInfo.hasNeuralEngine,
            totalMemoryMb: deviceInfo.totalMemoryMb,
            availableStorageMb: deviceInfo.availableStorageMb
        )

        let request = DeviceRegistrationRequest(
            deviceIdentifier: identifier,
            orgId: orgId,
            platform: "ios",
            osVersion: deviceInfo.osVersion,
            sdkVersion: "1.0.0",
            appVersion: appVersion,
            deviceInfo: hardwareInfo,
            locale: deviceInfo.locale,
            region: deviceInfo.region,
            timezone: deviceInfo.timezone,
            metadata: metadata,
            capabilities: capabilities
        )

        let registration = try await apiClient.registerDevice(request)

        // Store registration info
        self.serverDeviceId = registration.id
        self.deviceRegistration = registration

        // Store server device ID securely for persistence
        try? secureStorage.storeServerDeviceId(registration.id)

        // Start automatic heartbeat
        startHeartbeat()

        if configuration.enableLogging {
            logger.info("Device registered with ID: \(registration.id)")
        }

        return registration
    }

    // MARK: - Heartbeat

    /// Sends a heartbeat to the server.
    ///
    /// - Parameter availableStorageMb: Current available storage (optional).
    /// - Returns: Heartbeat response.
    /// - Throws: `EdgeMLError` if heartbeat fails.
    @discardableResult
    public func sendHeartbeat(availableStorageMb: Int? = nil) async throws -> HeartbeatResponse {
        guard let deviceId = self.deviceId else {
            throw EdgeMLError.deviceNotRegistered
        }

        var metadata: [String: String]? = nil
        if let availableStorageMb = availableStorageMb {
            metadata = ["available_storage_mb": String(availableStorageMb)]
        }

        let request = HeartbeatRequest(metadata: metadata)

        return try await apiClient.sendHeartbeat(deviceId: deviceId, request: request)
    }

    /// Starts automatic heartbeat reporting.
    public func startHeartbeat() {
        heartbeatTask?.cancel()

        heartbeatTask = Task { [weak self] in
            guard let self = self else { return }

            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(heartbeatInterval * 1_000_000_000))
                    _ = try await self.sendHeartbeat()
                    if self.configuration.enableLogging {
                        self.logger.debug("Heartbeat sent successfully")
                    }
                } catch {
                    if self.configuration.enableLogging {
                        self.logger.warning("Heartbeat failed: \(error.localizedDescription)")
                    }
                }
            }
        }
    }

    /// Stops automatic heartbeat reporting.
    public func stopHeartbeat() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
    }

    // MARK: - Device Groups

    /// Gets the groups this device belongs to.
    ///
    /// - Returns: List of device groups.
    /// - Throws: `EdgeMLError` if the request fails.
    public func getGroups() async throws -> [DeviceGroup] {
        guard let deviceId = self.deviceId else {
            throw EdgeMLError.deviceNotRegistered
        }

        return try await apiClient.getDeviceGroups(deviceId: deviceId)
    }

    /// Checks if this device belongs to a specific group.
    ///
    /// - Parameter groupId: The group ID to check.
    /// - Returns: True if device is a member of the group.
    /// - Throws: `EdgeMLError` if the request fails.
    public func isMemberOf(groupId: String) async throws -> Bool {
        let groups = try await getGroups()
        return groups.contains { $0.id == groupId }
    }

    /// Checks if this device belongs to a group with the given name.
    ///
    /// - Parameter groupName: The group name to check.
    /// - Returns: True if device is a member of a group with that name.
    /// - Throws: `EdgeMLError` if the request fails.
    public func isMemberOf(groupName: String) async throws -> Bool {
        let groups = try await getGroups()
        return groups.contains { $0.name == groupName }
    }

    /// Gets this device's full information from the server.
    ///
    /// - Returns: Full device information.
    /// - Throws: `EdgeMLError` if the request fails.
    public func getDeviceInfo() async throws -> DeviceInfo {
        guard let deviceId = self.deviceId else {
            throw EdgeMLError.deviceNotRegistered
        }

        return try await apiClient.getDeviceInfo(deviceId: deviceId)
    }

    // MARK: - Model Management

    /// Downloads a model from the server.
    ///
    /// The model is cached locally after download for offline use.
    ///
    /// - Parameters:
    ///   - modelId: Identifier of the model to download.
    ///   - version: Optional specific version. If nil, downloads the latest version.
    /// - Returns: The downloaded model ready for inference.
    /// - Throws: `EdgeMLError` if download fails.
    public func downloadModel(
        modelId: String,
        version: String? = nil
    ) async throws -> EdgeMLModel {
        guard let deviceId = self.deviceId else {
            throw EdgeMLError.deviceNotRegistered
        }

        if configuration.enableLogging {
            logger.info("Downloading model: \(modelId)")
        }

        // Resolve version if not specified
        let resolvedVersion: String
        if let version = version {
            resolvedVersion = version
        } else {
            let resolution = try await apiClient.resolveVersion(deviceId: deviceId, modelId: modelId)
            resolvedVersion = resolution.version
        }

        return try await modelManager.downloadModel(modelId: modelId, version: resolvedVersion)
    }

    /// Gets a cached model without network access.
    ///
    /// - Parameter modelId: Identifier of the model.
    /// - Returns: The cached model, or nil if not cached.
    public func getCachedModel(modelId: String) -> EdgeMLModel? {
        return modelManager.getCachedModel(modelId: modelId)
    }

    /// Gets a cached model with a specific version.
    ///
    /// - Parameters:
    ///   - modelId: Identifier of the model.
    ///   - version: Version of the model.
    /// - Returns: The cached model, or nil if not cached.
    public func getCachedModel(modelId: String, version: String) -> EdgeMLModel? {
        return modelManager.getCachedModel(modelId: modelId, version: version)
    }

    /// Checks if a model update is available.
    ///
    /// - Parameter modelId: Identifier of the model.
    /// - Returns: Update information if available, nil otherwise.
    /// - Throws: `EdgeMLError` if the check fails.
    public func checkForUpdates(modelId: String) async throws -> ModelUpdateInfo? {
        guard let cachedModel = getCachedModel(modelId: modelId) else {
            return nil
        }

        return try await apiClient.checkForUpdates(
            modelId: modelId,
            currentVersion: cachedModel.version
        )
    }

    /// Clears all cached models.
    public func clearCache() async throws {
        try await modelManager.clearCache()

        if configuration.enableLogging {
            logger.info("Model cache cleared")
        }
    }

    // MARK: - Streaming Inference

    /// Streams generative inference and auto-reports metrics to the server.
    ///
    /// - Parameters:
    ///   - model: The model to run inference on.
    ///   - input: Modality-specific input.
    ///   - modality: The output modality.
    ///   - engine: Optional custom engine. Defaults to a modality-appropriate engine.
    /// - Returns: An ``AsyncThrowingStream`` of ``InferenceChunk``.
    public func generateStream(
        model: EdgeMLModel,
        input: Any,
        modality: Modality,
        engine: StreamingInferenceEngine? = nil
    ) -> AsyncThrowingStream<InferenceChunk, Error> {
        let (stream, getResult) = model.generateStream(input: input, modality: modality, engine: engine)
        let apiClient = self.apiClient
        let deviceId = self.deviceId
        let orgId = self.orgId
        let sessionId = UUID().uuidString

        // Report generation_started
        if let deviceId = deviceId {
            Task {
                let ctx = InferenceEventContext(
                    deviceId: deviceId,
                    modelId: model.id,
                    version: model.version,
                    modality: modality.rawValue,
                    sessionId: sessionId
                )
                let event = InferenceEventRequest(
                    context: ctx,
                    eventType: "generation_started",
                    timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
                    orgId: orgId
                )
                try? await apiClient.reportInferenceEvent(event)
            }
        }

        // Wrap the stream to report completion
        return AsyncThrowingStream<InferenceChunk, Error> { continuation in
            let task = Task {
                var failed = false
                do {
                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                } catch {
                    failed = true
                    continuation.finish(throwing: error)
                }

                if !failed {
                    continuation.finish()
                }

                // Report completion event
                if let deviceId = deviceId, let result = getResult() {
                    let metrics = InferenceEventMetrics(
                        ttfcMs: result.ttfcMs,
                        totalChunks: result.totalChunks,
                        totalDurationMs: result.totalDurationMs,
                        throughput: result.throughput
                    )
                    let ctx = InferenceEventContext(
                        deviceId: deviceId,
                        modelId: model.id,
                        version: model.version,
                        modality: modality.rawValue,
                        sessionId: sessionId
                    )
                    let event = InferenceEventRequest(
                        context: ctx,
                        eventType: failed ? "generation_failed" : "generation_completed",
                        timestampMs: Int64(Date().timeIntervalSince1970 * 1000),
                        metrics: metrics,
                        orgId: orgId
                    )
                    try? await apiClient.reportInferenceEvent(event)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - Training

    /// Participates in a federated training round.
    ///
    /// This method:
    /// 1. Downloads the latest model if needed
    /// 2. Trains the model on local data
    /// 3. Extracts weight updates
    /// 4. Uploads updates to the server
    ///
    /// - Parameters:
    ///   - modelId: Identifier of the model to train.
    ///   - dataProvider: Closure that provides training data.
    ///   - config: Training configuration.
    /// - Returns: Result of the training round.
    /// - Throws: `EdgeMLError` if training fails.
    public func participateInRound(
        modelId: String,
        dataProvider: @escaping () -> MLBatchProvider,
        config: TrainingConfig = .standard
    ) async throws -> RoundResult {
        guard let deviceId = self.deviceId else {
            throw EdgeMLError.deviceNotRegistered
        }

        if configuration.enableLogging {
            logger.info("Participating in training round for model: \(modelId)")
        }

        // Get or download model
        let model: EdgeMLModel
        if let cached = getCachedModel(modelId: modelId) {
            // Check for updates
            if let updateInfo = try? await checkForUpdates(modelId: modelId), updateInfo.isRequired {
                model = try await downloadModel(modelId: modelId, version: updateInfo.newVersion)
            } else {
                model = cached
            }
        } else {
            model = try await downloadModel(modelId: modelId)
        }

        // Train locally
        let trainer = FederatedTrainer(configuration: configuration)
        let trainingResult = try await trainer.train(
            model: model,
            dataProvider: dataProvider,
            config: config
        )

        // Extract and upload weights
        var weightUpdate = try await trainer.extractWeightUpdate(
            model: model,
            trainingResult: trainingResult
        )
        weightUpdate = WeightUpdate(
            modelId: weightUpdate.modelId,
            version: weightUpdate.version,
            deviceId: deviceId,
            weightsData: weightUpdate.weightsData,
            sampleCount: weightUpdate.sampleCount,
            metrics: weightUpdate.metrics
        )

        try await apiClient.uploadWeights(weightUpdate)

        let roundResult = RoundResult(
            roundId: UUID().uuidString,
            trainingResult: trainingResult,
            uploadSucceeded: true,
            completedAt: Date()
        )

        if configuration.enableLogging {
            logger.info("Training round completed: \(trainingResult.sampleCount) samples")
        }

        return roundResult
    }

    /// Trains a model locally without uploading weights.
    ///
    /// Useful for testing and validation.
    ///
    /// - Parameters:
    ///   - model: The model to train.
    ///   - data: Training data provider.
    ///   - config: Training configuration.
    /// - Returns: Training result.
    /// - Throws: `EdgeMLError` if training fails.
    public func trainLocal(
        model: EdgeMLModel,
        data: MLBatchProvider,
        config: TrainingConfig = .standard
    ) async throws -> TrainingResult {
        let trainer = FederatedTrainer(configuration: configuration)
        return try await trainer.train(
            model: model,
            dataProvider: { data },
            config: config
        )
    }

    // MARK: - Background Operations

    /// Enables background training when conditions are met.
    ///
    /// Background training runs during device idle time when:
    /// - Device is connected to power (optional)
    /// - Network is available
    /// - Battery level is sufficient
    ///
    /// - Parameters:
    ///   - modelId: Identifier of the model to train.
    ///   - dataProvider: Closure that provides training data.
    ///   - constraints: Background execution constraints.
    public func enableBackgroundTraining(
        modelId: String,
        dataProvider: @escaping @Sendable () -> MLBatchProvider,
        constraints: BackgroundConstraints = .standard
    ) {
        let sync = BackgroundSync.shared
        sync.configure(
            modelId: modelId,
            dataProvider: dataProvider,
            constraints: constraints,
            client: self
        )
        sync.scheduleNextTraining()

        if configuration.enableLogging {
            logger.info("Background training enabled for model: \(modelId)")
        }
    }

    /// Disables background training.
    public func disableBackgroundTraining() {
        BackgroundSync.shared.cancelScheduledTraining()

        if configuration.enableLogging {
            logger.info("Background training disabled")
        }
    }

    // MARK: - Event Tracking

    /// Tracks an event for an experiment.
    ///
    /// - Parameters:
    ///   - experimentId: Experiment identifier.
    ///   - eventName: Name of the event.
    ///   - properties: Event properties.
    public func trackEvent(
        experimentId: String,
        eventName: String,
        properties: [String: String] = [:]
    ) async throws {
        let event = TrackingEvent(
            name: eventName,
            properties: properties,
            timestamp: Date()
        )

        try await apiClient.trackEvent(experimentId: experimentId, event: event)
    }

    // MARK: - Private Methods

    /// Device info collected during registration.
    private struct LocalDeviceInfo {
        let osVersion: String
        let deviceModel: String
        let totalMemoryMb: Int?
        let availableStorageMb: Int?
        let locale: String?
        let region: String?
        let timezone: String?
        let supportsTraining: Bool
        let coremlVersion: String?
        let hasNeuralEngine: Bool
    }

    private func buildDeviceInfo() async -> LocalDeviceInfo {
        var availableStorageMb: Int? = nil
        var totalMemoryMb: Int? = nil
        let deviceModel: String
        let osVersion: String

        #if canImport(UIKit)
        // Get storage info
        if let attrs = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
           let freeSize = attrs[.systemFreeSize] as? UInt64 {
            availableStorageMb = Int(freeSize / (1024 * 1024))
        }

        // Get total memory
        totalMemoryMb = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024))

        let deviceInfo = await MainActor.run {
            (model: UIDevice.current.model, os: UIDevice.current.systemVersion)
        }
        deviceModel = deviceInfo.model
        osVersion = deviceInfo.os
        #else
        osVersion = ProcessInfo.processInfo.operatingSystemVersionString
        deviceModel = "Mac"
        totalMemoryMb = Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024))
        #endif

        // Get locale info
        let currentLocale = Locale.current
        let locale = currentLocale.identifier
        let region: String?
        if #available(iOS 16.0, macOS 13.0, *) {
            region = currentLocale.region?.identifier
        } else {
            region = (currentLocale as NSLocale).countryCode
        }
        let timezone = TimeZone.current.identifier

        return LocalDeviceInfo(
            osVersion: osVersion,
            deviceModel: deviceModel,
            totalMemoryMb: totalMemoryMb,
            availableStorageMb: availableStorageMb,
            locale: locale,
            region: region,
            timezone: timezone,
            supportsTraining: true, // iOS 15+ supports on-device training
            coremlVersion: "5.0",
            hasNeuralEngine: hasNeuralEngine()
        )
    }

    private func generateDeviceIdentifier() -> String {
        #if canImport(UIKit)
        // Use IDFV (Identifier for Vendor) on iOS
        if let idfv = UIDevice.current.identifierForVendor?.uuidString {
            return idfv
        }
        #endif
        // Fallback to a generated UUID stored in keychain
        if let storedId = try? secureStorage.getClientDeviceIdentifier() {
            return storedId
        }
        let newId = UUID().uuidString
        try? secureStorage.storeClientDeviceIdentifier(newId)
        return newId
    }

    private func hasNeuralEngine() -> Bool {
        // Check for Neural Engine availability
        #if canImport(UIKit)
        // A12 Bionic and later have Neural Engine
        // This is a simplified check - in production, use device model mapping
        return true
        #else
        return false
        #endif
    }
}
