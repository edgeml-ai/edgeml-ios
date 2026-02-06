//
//  DeviceInfo.swift
//  EdgeML iOS SDK
//
//  Collects device hardware metadata and runtime constraints
//  for monitoring and training eligibility.
//

import Foundation
import UIKit
import CoreTelephony
import Network

/// Collects and manages device information for EdgeML platform.
///
/// Automatically gathers:
/// - Stable device identifier (IDFV)
/// - Hardware specs (CPU, memory, storage, GPU)
/// - System info (iOS version, model)
/// - Runtime constraints (battery, network)
/// - Locale and timezone
///
/// Example:
/// ```swift
/// let deviceInfo = DeviceInfo()
/// let registrationData = deviceInfo.toRegistrationDict()
/// ```
public class DeviceInfo {

    // MARK: - Properties

    /// Stable device identifier (IDFV - Identifier For Vendor)
    public var deviceId: String {
        return UIDevice.current.identifierForVendor?.uuidString ?? UUID().uuidString
    }

    private let reachability = Reachability()

    // MARK: - Device Hardware

    /// Get device manufacturer (always "Apple" for iOS)
    public var manufacturer: String {
        return "Apple"
    }

    /// Get device model (e.g., "iPhone 15 Pro", "iPad Air")
    public var model: String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }
        return modelCode ?? UIDevice.current.model
    }

    /// Get CPU architecture (arm64)
    public var cpuArchitecture: String {
        #if arch(arm64)
        return "arm64"
        #elseif arch(x86_64)
        return "x86_64"
        #else
        return "unknown"
        #endif
    }

    /// Check if Neural Engine (GPU) is available
    public var gpuAvailable: Bool {
        // iOS devices from A11 Bionic onward have Neural Engine
        if #available(iOS 11.0, *) {
            return true
        }
        return false
    }

    /// Get total physical memory in MB
    public var totalMemoryMB: Int? {
        return Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024))
    }

    /// Get available storage space in MB
    public var availableStorageMB: Int? {
        guard let path = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true).first else {
            return nil
        }

        do {
            let attributes = try FileManager.default.attributesOfFileSystem(forPath: path)
            if let freeSize = attributes[.systemFreeSize] as? NSNumber {
                return Int(freeSize.int64Value / (1024 * 1024))
            }
        } catch {
            return nil
        }
        return nil
    }

    // MARK: - Runtime Constraints

    /// Get current battery level (0-100)
    public var batteryLevel: Int? {
        UIDevice.current.isBatteryMonitoringEnabled = true
        let level = UIDevice.current.batteryLevel
        UIDevice.current.isBatteryMonitoringEnabled = false

        if level < 0 {
            return nil  // Battery level unknown
        }
        return Int(level * 100)
    }

    /// Get current network type (wifi, cellular, unknown)
    public var networkType: String {
        switch reachability.connection {
        case .wifi:
            return "wifi"
        case .cellular:
            return "cellular"
        case .unavailable:
            return "offline"
        case .none:
            return "unknown"
        }
    }

    // MARK: - System Info

    /// Get iOS platform string
    public var platform: String {
        return "ios"
    }

    /// Get iOS version
    public var osVersion: String {
        return UIDevice.current.systemVersion
    }

    /// Get user's locale
    public var locale: String {
        return Locale.current.identifier
    }

    /// Get user's region
    public var region: String {
        return Locale.current.regionCode ?? "US"
    }

    /// Get user's timezone
    public var timezone: String {
        return TimeZone.current.identifier
    }

    // MARK: - Collection Methods

    /// Collect complete device hardware information
    public func collectDeviceInfo() -> [String: Any] {
        var info: [String: Any] = [
            "manufacturer": manufacturer,
            "model": model,
            "cpu_architecture": cpuArchitecture,
            "gpu_available": gpuAvailable
        ]

        if let memory = totalMemoryMB {
            info["total_memory_mb"] = memory
        }

        if let storage = availableStorageMB {
            info["available_storage_mb"] = storage
        }

        return info
    }

    /// Collect runtime metadata (battery, network)
    public func collectMetadata() -> [String: Any] {
        var metadata: [String: Any] = [
            "network_type": networkType
        ]

        if let battery = batteryLevel {
            metadata["battery_level"] = battery
        }

        return metadata
    }

    /// Collect ML capabilities
    public func collectCapabilities() -> [String: Any] {
        return [
            "cpu_architecture": cpuArchitecture,
            "gpu_available": gpuAvailable,
            "coreml": true,
            "neural_engine": gpuAvailable
        ]
    }

    /// Create registration payload for EdgeML API
    public func toRegistrationDict() -> [String: Any] {
        return [
            "device_identifier": deviceId,
            "platform": platform,
            "os_version": osVersion,
            "device_info": collectDeviceInfo(),
            "locale": locale,
            "region": region,
            "timezone": timezone,
            "metadata": collectMetadata(),
            "capabilities": collectCapabilities()
        ]
    }

    /// Get updated metadata for heartbeat updates
    ///
    /// Call this periodically to send updated battery/network status.
    public func updateMetadata() -> [String: Any] {
        return collectMetadata()
    }
}

// MARK: - Reachability Helper

/// Network.framework-based reachability for network type detection.
fileprivate final class Reachability {
    enum Connection {
        case unavailable
        case wifi
        case cellular
        case none
    }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "ai.edgeml.sdk.reachability")
    private var latestPath: NWPath?

    init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.latestPath = path
        }
        monitor.start(queue: queue)
        latestPath = monitor.currentPath
    }

    deinit {
        monitor.cancel()
    }

    var connection: Connection {
        let path = latestPath ?? monitor.currentPath
        guard path.status == .satisfied else {
            return .unavailable
        }
        if path.usesInterfaceType(.wifi) {
            return .wifi
        }
        if path.usesInterfaceType(.cellular) {
            return .cellular
        }
        return .none
    }
}
