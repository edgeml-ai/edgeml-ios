//
//  DiscoveryManager.swift
//  EdgeML iOS SDK
//
//  High-level manager for making a device discoverable on the local network.
//  Wraps BonjourAdvertiser with a simple start/stop API.
//

import Foundation
import os.log

/// Manages local network discoverability for this device.
///
/// When discoverable, the EdgeML CLI (`edgeml deploy --phone`) can find this
/// device via mDNS and initiate model deployment without QR codes.
///
/// Call ``startDiscoverable(deviceId:)`` when the app is in the foreground and
/// ready to receive deployments. Call ``stopDiscoverable()`` when backgrounded
/// or no longer accepting deployments.
///
/// # Example
///
/// ```swift
/// let discovery = DiscoveryManager()
///
/// // App entered foreground / user tapped "Receive Model"
/// discovery.startDiscoverable(deviceId: "device_abc123")
///
/// // App backgrounded
/// discovery.stopDiscoverable()
/// ```
///
/// # Thread Safety
///
/// All mutable state is protected by `NSLock`. Start and stop are idempotent.
public final class DiscoveryManager: @unchecked Sendable {

    // MARK: - Properties

    private let lock = NSLock()
    private let logger: Logger
    private var advertiser: BonjourAdvertiser?

    /// Whether the device is currently discoverable on the local network.
    public var isDiscoverable: Bool {
        lock.lock()
        defer { lock.unlock() }
        return advertiser?.isAdvertising ?? false
    }

    // MARK: - Initialization

    /// Creates a new discovery manager.
    public init() {
        self.logger = Logger(subsystem: "ai.edgeml.sdk", category: "DiscoveryManager")
    }

    // MARK: - Public API

    /// Start making this device discoverable on the local network.
    ///
    /// Creates a ``BonjourAdvertiser`` and begins advertising an `_edgeml._tcp`
    /// Bonjour service. The EdgeML CLI will be able to find this device by
    /// scanning the local network.
    ///
    /// Calling this when already discoverable is a no-op.
    ///
    /// - Parameters:
    ///   - deviceId: Unique identifier for this device.
    ///   - deviceName: Optional human-readable device name.
    ///                 Defaults to the system device name.
    ///   - port: TCP port to advertise. Defaults to 0 (ephemeral).
    public func startDiscoverable(
        deviceId: String,
        deviceName: String? = nil,
        port: UInt16 = 0
    ) {
        lock.lock()
        if advertiser?.isAdvertising == true {
            lock.unlock()
            return
        }
        lock.unlock()

        let newAdvertiser = BonjourAdvertiser(deviceId: deviceId, deviceName: deviceName)

        do {
            try newAdvertiser.startAdvertising(port: port)

            lock.lock()
            self.advertiser = newAdvertiser
            lock.unlock()

            logger.info("Device is now discoverable (deviceId=\(deviceId))")
        } catch {
            logger.error("Failed to start discovery: \(error.localizedDescription)")
        }
    }

    /// Stop advertising this device on the local network.
    ///
    /// Calling this when not discoverable is a no-op.
    public func stopDiscoverable() {
        lock.lock()
        guard let currentAdvertiser = advertiser else {
            lock.unlock()
            return
        }
        advertiser = nil
        lock.unlock()

        currentAdvertiser.stopAdvertising()
        logger.info("Device is no longer discoverable")
    }
}
