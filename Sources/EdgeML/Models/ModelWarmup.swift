import Foundation

// MARK: - Warmup Result

/// Result of a warmup pass including delegate benchmark.
///
/// Captures timing information from cold and warm inference passes,
/// and records which compute delegate (Neural Engine, GPU, CPU) is active
/// after warmup validation.
public struct WarmupResult: Sendable {
    /// First inference time in milliseconds (includes JIT/shader/delegate init).
    public let coldInferenceMs: Double

    /// Second inference time in milliseconds (steady-state latency with selected delegate).
    public let warmInferenceMs: Double

    /// CPU-only warm latency in milliseconds, if a hardware accelerator was benchmarked.
    /// Nil when no accelerator was active.
    public let cpuInferenceMs: Double?

    /// Whether the Neural Engine is active after warmup.
    public let usingNeuralEngine: Bool

    /// Which delegate survived warmup validation: "neural_engine", "gpu", or "cpu".
    public let activeDelegate: String

    /// Delegates that were disabled during warmup cascade
    /// (e.g., ["neural_engine", "gpu"] if both were slower than CPU).
    public let disabledDelegates: [String]

    public init(
        coldInferenceMs: Double,
        warmInferenceMs: Double,
        cpuInferenceMs: Double? = nil,
        usingNeuralEngine: Bool,
        activeDelegate: String,
        disabledDelegates: [String] = []
    ) {
        self.coldInferenceMs = coldInferenceMs
        self.warmInferenceMs = warmInferenceMs
        self.cpuInferenceMs = cpuInferenceMs
        self.usingNeuralEngine = usingNeuralEngine
        self.activeDelegate = activeDelegate
        self.disabledDelegates = disabledDelegates
    }

    /// True if any delegate was disabled during warmup.
    public var delegateDisabled: Bool {
        !disabledDelegates.isEmpty
    }
}
