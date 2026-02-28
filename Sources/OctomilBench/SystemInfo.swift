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

    public var summary: String {
        "\(chipName) | \(memoryGb)GB RAM | macOS \(osVersion)"
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
