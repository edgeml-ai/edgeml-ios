import Foundation

/// Pure-function checks for whether the device is eligible to perform training.
///
/// Uses ``DeviceStateMonitor/DeviceState`` and ``OctomilConfiguration/TrainingPolicy``
/// to decide if training should proceed, without side effects.
public enum TrainingEligibility {

    /// Checks whether the device is eligible for training given current state and policy.
    ///
    /// Checks are evaluated in priority order:
    /// 1. Low Power Mode — always blocks training
    /// 2. Thermal pressure — serious or critical blocks training
    /// 3. Charging requirement — if policy requires charging
    /// 4. Battery level — unless device is charging or full
    ///
    /// - Parameters:
    ///   - deviceState: Current device state snapshot.
    ///   - policy: Training policy from configuration.
    /// - Returns: An ``EligibilityResult`` indicating whether training can proceed.
    public static func check(
        deviceState: DeviceStateMonitor.DeviceState,
        policy: OctomilConfiguration.TrainingPolicy
    ) -> EligibilityResult {
        // Low Power Mode always blocks training
        if deviceState.isLowPowerMode {
            return EligibilityResult(eligible: false, reason: .lowPowerMode)
        }

        // Thermal pressure: serious or critical
        if deviceState.thermalState >= .serious {
            return EligibilityResult(eligible: false, reason: .thermalPressure)
        }

        // Charging requirement
        let isPluggedIn = deviceState.batteryState == .charging || deviceState.batteryState == .full
        if policy.requireChargingForTraining && !isPluggedIn {
            return EligibilityResult(eligible: false, reason: .notCharging)
        }

        // Battery level (skip check if plugged in)
        if !isPluggedIn && deviceState.batteryLevel < policy.minimumBatteryLevel {
            return EligibilityResult(eligible: false, reason: .lowBattery)
        }

        return EligibilityResult(eligible: true, reason: nil)
    }

    /// Assesses whether the current network conditions are suitable for gradient upload.
    ///
    /// - Parameters:
    ///   - isConnected: Whether a network connection exists.
    ///   - isExpensive: Whether the connection is metered (cellular).
    ///   - isConstrained: Whether Low Data Mode is enabled.
    /// - Returns: A ``NetworkQualityResult`` indicating upload suitability.
    public static func assessNetworkQuality(
        isConnected: Bool,
        isExpensive: Bool,
        isConstrained: Bool
    ) -> NetworkQualityResult {
        guard isConnected else {
            return NetworkQualityResult(suitable: false, reason: .noConnection)
        }

        if isExpensive {
            return NetworkQualityResult(suitable: false, reason: .expensiveNetwork)
        }

        if isConstrained {
            return NetworkQualityResult(suitable: false, reason: .constrainedNetwork)
        }

        return NetworkQualityResult(suitable: true, reason: nil)
    }
}
