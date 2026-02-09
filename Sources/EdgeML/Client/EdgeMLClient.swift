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

    let apiClient: APIClient
    let modelManager: ModelManager
    fileprivate let secureStorage: SecureStorage
    let configuration: EdgeMLConfiguration
    let logger: Logger

    /// Organization ID for this client.
    public let orgId: String

    /// Server-assigned device UUID (set after registration).
    fileprivate var serverDeviceId: String?
    /// Client-generated device identifier (e.g., IDFV).
    fileprivate var clientDeviceIdentifier: String?
    fileprivate var deviceRegistration: DeviceRegistrationResponse?

    /// Heartbeat timer for automatic health reporting.
    fileprivate var heartbeatTask: Task<Void, Never>?
    fileprivate let heartbeatInterval: TimeInterval

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
}

// MARK: - Device Registration

extension EdgeMLClient {

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

        let request = buildRegistrationRequest(
            identifier: identifier,
            appVersion: appVersion,
            metadata: metadata,
            deviceInfo: deviceInfo
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
}

// MARK: - Heartbeat

extension EdgeMLClient {

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

        var metadata: [String: String]?
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
}

// MARK: - Device Groups

extension EdgeMLClient {

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
}

// MARK: - Private Helpers

extension EdgeMLClient {

    /// Device info collected during registration.
    fileprivate struct LocalDeviceInfo {
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

    fileprivate func buildDeviceInfo() async -> LocalDeviceInfo {
        var availableStorageMb: Int?
        var totalMemoryMb: Int?
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

    fileprivate func generateDeviceIdentifier() -> String {
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

    fileprivate func hasNeuralEngine() -> Bool {
        // Check for Neural Engine availability
        #if canImport(UIKit)
        // A12 Bionic and later have Neural Engine
        // This is a simplified check - in production, use device model mapping
        return true
        #else
        return false
        #endif
    }

    fileprivate func buildRegistrationRequest(
        identifier: String,
        appVersion: String?,
        metadata: [String: String]?,
        deviceInfo: LocalDeviceInfo
    ) -> DeviceRegistrationRequest {
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

        return DeviceRegistrationRequest(
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
    }

    func resolveModelForTraining(modelId: String) async throws -> EdgeMLModel {
        if let cached = getCachedModel(modelId: modelId) {
            if let updateInfo = try? await checkForUpdates(modelId: modelId),
               updateInfo.isRequired {
                return try await downloadModel(modelId: modelId, version: updateInfo.newVersion)
            }
            return cached
        }
        return try await downloadModel(modelId: modelId)
    }
}
