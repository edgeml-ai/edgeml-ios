import Foundation

/// Samples GPU and CPU power draw using macOS `powermetrics`.
/// Requires root access — returns nil values if unavailable.
public final class PowerSampler: @unchecked Sendable {
    private var process: Process?
    private var pipe: Pipe?
    private var samples: [(gpu: Double, cpu: Double)] = []
    private let queue = DispatchQueue(label: "power-sampler")

    /// Start sampling power at ~500ms intervals.
    public func start() {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/powermetrics")
        proc.arguments = [
            "--samplers", "cpu_power,gpu_power",
            "-i", "500",
            "--format", "text",
        ]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        self.process = proc
        self.pipe = pipe

        // Read output line-by-line on background queue
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            self?.queue.sync {
                self?.parseOutput(text)
            }
        }

        do {
            try proc.run()
        } catch {
            // No root access or powermetrics unavailable
            self.process = nil
            self.pipe = nil
        }
    }

    /// Stop sampling and return average power readings.
    public func stop() -> PowerReading? {
        process?.terminate()
        process?.waitUntilExit()
        pipe?.fileHandleForReading.readabilityHandler = nil

        return queue.sync {
            guard !samples.isEmpty else { return nil }
            let avgGpu = samples.map(\.gpu).reduce(0, +) / Double(samples.count)
            let avgCpu = samples.map(\.cpu).reduce(0, +) / Double(samples.count)
            return PowerReading(gpuW: avgGpu, cpuW: avgCpu, sampleCount: samples.count)
        }
    }

    private var buffer = ""
    private var currentGpu: Double?
    private var currentCpu: Double?

    private func parseOutput(_ text: String) {
        buffer += text
        let lines = buffer.split(separator: "\n", omittingEmptySubsequences: false)
        // Keep last incomplete line in buffer
        buffer = lines.last.map(String.init) ?? ""

        for line in lines.dropLast() {
            let s = String(line).trimmingCharacters(in: .whitespaces)

            // "GPU Power: 5432 mW"
            if s.hasPrefix("GPU Power:"), let mw = parseMilliwatts(s) {
                currentGpu = mw / 1000.0
            }
            // "CPU Power: 1234 mW" or "Package Power: 6789 mW"
            if s.hasPrefix("CPU Power:"), let mw = parseMilliwatts(s) {
                currentCpu = mw / 1000.0
            }

            // Emit sample when we have both
            if let gpu = currentGpu, let cpu = currentCpu {
                samples.append((gpu: gpu, cpu: cpu))
                currentGpu = nil
                currentCpu = nil
            }
        }
    }

    private func parseMilliwatts(_ line: String) -> Double? {
        // "GPU Power: 5432 mW" → 5432.0
        let parts = line.split(separator: ":")
        guard parts.count >= 2 else { return nil }
        let valueStr = parts[1].trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: " mW", with: "")
        return Double(valueStr)
    }
}

public struct PowerReading: Codable, Sendable {
    public let gpuW: Double
    public let cpuW: Double
    public let sampleCount: Int

    public var totalW: Double { gpuW + cpuW }
}
