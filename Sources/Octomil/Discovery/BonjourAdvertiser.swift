//
//  BonjourAdvertiser.swift
//  Octomil iOS SDK
//
//  Advertises an Octomil device on the local network via Bonjour (mDNS)
//  so that the CLI (`octomil deploy --phone`) can discover it.
//

import Foundation
import Network
import os.log
#if canImport(UIKit)
import UIKit
#endif

/// Advertises this device on the local network using Bonjour/mDNS
/// so the Octomil CLI can discover it for model deployment.
///
/// Uses `NWListener` from Network.framework (not the deprecated `NetService`).
///
/// The listener advertises an `_octomil._tcp` service with TXT record metadata
/// including the device ID, platform, and device name. It does not accept
/// connections -- actual pairing happens via the server API.
///
/// # Example
///
/// ```swift
/// let advertiser = BonjourAdvertiser(deviceId: "device_abc123")
/// try advertiser.startAdvertising()
/// // Device is now discoverable by `octomil deploy --phone`
/// advertiser.stopAdvertising()
/// ```
///
/// # Thread Safety
///
/// All mutable state is protected by `NSLock`. Start and stop are idempotent.
public final class BonjourAdvertiser: @unchecked Sendable {

    // MARK: - Constants

    /// Bonjour service type for Octomil device discovery.
    public static let serviceType = "_octomil._tcp"

    // MARK: - Properties

    private let deviceId: String
    private let deviceName: String
    private let logger: Logger
    private let lock = NSLock()

    private var listener: NWListener?
    private var _isAdvertising = false

    /// Whether the advertiser is currently broadcasting on the local network.
    public var isAdvertising: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _isAdvertising
    }

    // MARK: - Initialization

    /// Creates a new Bonjour advertiser.
    ///
    /// - Parameters:
    ///   - deviceId: Unique identifier for this device (sent in the TXT record).
    ///   - deviceName: Human-readable device name. Defaults to the system device name.
    public init(deviceId: String, deviceName: String? = nil) {
        self.deviceId = deviceId
        self.deviceName = deviceName ?? Self.defaultDeviceName()
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "BonjourAdvertiser")
    }

    // MARK: - Public API

    /// Start advertising this device on the local network.
    ///
    /// Creates an `NWListener` bound to the given port (or an ephemeral port
    /// if `port` is 0) and registers a Bonjour service with TXT record metadata.
    ///
    /// Calling this when already advertising is a no-op.
    ///
    /// - Parameter port: TCP port to advertise. Defaults to 0 (ephemeral).
    /// - Throws: If the listener cannot be created.
    public func startAdvertising(port: UInt16 = 0) throws {
        lock.lock()
        if _isAdvertising {
            lock.unlock()
            return
        }
        lock.unlock()

        let parameters = NWParameters.tcp
        let nwPort: NWEndpoint.Port = port == 0 ? .any : NWEndpoint.Port(rawValue: port)!

        let newListener: NWListener
        do {
            newListener = try NWListener(using: parameters, on: nwPort)
        } catch {
            logger.error("Failed to create NWListener: \(error.localizedDescription)")
            throw error
        }

        // Build TXT record
        let txtRecord = buildTXTRecord()

        // Configure Bonjour service
        newListener.service = NWListener.Service(
            name: deviceName,
            type: Self.serviceType,
            txtRecord: txtRecord
        )

        // State handler
        newListener.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.logger.info("Bonjour advertising started for device \(self.deviceId)")
            case .failed(let error):
                self.logger.error("Bonjour advertising failed: \(error.localizedDescription)")
                self.stopAdvertising()
            case .cancelled:
                self.logger.debug("Bonjour advertising cancelled")
            default:
                break
            }
        }

        // We don't need to accept connections -- the listener just advertises.
        // Set a handler that immediately cancels any incoming connection.
        newListener.newConnectionHandler = { connection in
            connection.cancel()
        }

        let queue = DispatchQueue(label: "ai.octomil.bonjour")
        newListener.start(queue: queue)

        lock.lock()
        self.listener = newListener
        self._isAdvertising = true
        lock.unlock()
    }

    /// Stop advertising this device on the local network.
    ///
    /// Calling this when not advertising is a no-op.
    public func stopAdvertising() {
        lock.lock()
        guard _isAdvertising, let currentListener = listener else {
            lock.unlock()
            return
        }
        _isAdvertising = false
        listener = nil
        lock.unlock()

        currentListener.cancel()
        logger.debug("Stopped Bonjour advertising for device \(self.deviceId)")
    }

    // MARK: - TXT Record

    /// Builds the Bonjour TXT record with device metadata.
    ///
    /// Keys:
    /// - `device_id`: Unique device identifier
    /// - `platform`: Always `ios` on iOS, `macos` on macOS
    /// - `device_name`: Human-readable device name
    internal func buildTXTRecord() -> NWTXTRecord {
        var txt = NWTXTRecord()
        txt["device_id"] = deviceId
        txt["platform"] = Self.currentPlatform()
        txt["device_name"] = deviceName
        return txt
    }

    // MARK: - Platform Helpers

    /// Returns the current platform string.
    internal static func currentPlatform() -> String {
        #if os(iOS)
        return "ios"
        #elseif os(macOS)
        return "macos"
        #else
        return "unknown"
        #endif
    }

    /// Returns the default device name for the current platform.
    internal static func defaultDeviceName() -> String {
        #if canImport(UIKit) && !os(watchOS)
        return UIDevice.current.name
        #elseif os(macOS)
        return Host.current().localizedName ?? "Mac"
        #else
        return "Octomil Device"
        #endif
    }
}
