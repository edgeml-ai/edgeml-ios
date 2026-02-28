import Foundation

/// Collects system hardware information via sysctl.
public struct SystemInfo: Codable, Sendable {
    public let chipName: String
    public let cpuCores: Int
    public let gpuCores: Int
    public let memoryGb: Int
    public let osVersion: String

    public static func collect() -> SystemInfo {
        SystemInfo(
            chipName: sysctl(name: "machdep.cpu.brand_string") ?? "Unknown",
            cpuCores: sysctlInt(name: "hw.ncpu") ?? 0,
            gpuCores: sysctlInt(name: "hw.perflevel0.logicalcpu") ?? 0,
            memoryGb: (sysctlInt(name: "hw.memsize") ?? 0) / (1024 * 1024 * 1024),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }

    /// Theoretical peak memory bandwidth (GB/s) for known Apple Silicon chips.
    public var peakBandwidthGBs: Double? {
        let chip = chipName.lowercased()
        if chip.contains("m4 pro") { return 273 }
        if chip.contains("m4 max") { return 546 }
        if chip.contains("m4 ultra") { return 819 }
        if chip.contains("m4") { return 120 }
        if chip.contains("m3 pro") { return 150 }
        if chip.contains("m3 max") { return 400 }
        if chip.contains("m3 ultra") { return 800 }
        if chip.contains("m3") { return 100 }
        if chip.contains("m2 pro") { return 200 }
        if chip.contains("m2 max") { return 400 }
        if chip.contains("m2 ultra") { return 800 }
        if chip.contains("m2") { return 100 }
        if chip.contains("m1 pro") { return 200 }
        if chip.contains("m1 max") { return 400 }
        if chip.contains("m1 ultra") { return 800 }
        if chip.contains("m1") { return 68 }
        return nil
    }

    public var summary: String {
        var s = "\(chipName) | \(memoryGb)GB RAM | macOS \(osVersion)"
        if let bw = peakBandwidthGBs {
            s += " | Peak BW: \(Int(bw)) GB/s"
        }
        return s
    }

    private static func sysctl(name: String) -> String? {
        var size = 0
        sysctlbyname(name, nil, &size, nil, 0)
        guard size > 0 else { return nil }
        var value = [CChar](repeating: 0, count: size)
        sysctlbyname(name, &value, &size, nil, 0)
        return String(cString: value).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func sysctlInt(name: String) -> Int? {
        var value: Int = 0
        var size = MemoryLayout<Int>.size
        let result = sysctlbyname(name, &value, &size, nil, 0)
        return result == 0 ? value : nil
    }
}
