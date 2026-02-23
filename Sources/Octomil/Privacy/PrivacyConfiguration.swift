import Foundation

/// Configuration for privacy-preserving upload behavior.
public struct PrivacyConfiguration {

    /// Whether to enable staggered updates (random delays before upload).
    public let enableStaggeredUpdates: Bool

    /// Minimum delay before upload (seconds).
    public let minUploadDelaySeconds: Double

    /// Maximum delay before upload (seconds).
    public let maxUploadDelaySeconds: Double

    /// Whether to enable differential privacy (noise injection).
    public let enableDifferentialPrivacy: Bool

    /// Privacy budget (epsilon) for differential privacy.
    /// Smaller values = more private (more noise).
    public let dpEpsilon: Double

    /// Gradient clipping norm for differential privacy.
    public let dpClippingNorm: Double

    /// Creates a privacy configuration.
    /// - Parameters:
    ///   - enableStaggeredUpdates: Enable random upload delays (default: true)
    ///   - minUploadDelaySeconds: Minimum delay in seconds (default: 0)
    ///   - maxUploadDelaySeconds: Maximum delay in seconds (default: 300 = 5 minutes)
    ///   - enableDifferentialPrivacy: Enable DP noise injection (default: false)
    ///   - dpEpsilon: Privacy budget (default: 1.0)
    ///   - dpClippingNorm: Gradient clipping threshold (default: 1.0)
    public init(
        enableStaggeredUpdates: Bool = true,
        minUploadDelaySeconds: Double = 0,
        maxUploadDelaySeconds: Double = 300,
        enableDifferentialPrivacy: Bool = false,
        dpEpsilon: Double = 1.0,
        dpClippingNorm: Double = 1.0
    ) {
        self.enableStaggeredUpdates = enableStaggeredUpdates
        self.minUploadDelaySeconds = minUploadDelaySeconds
        self.maxUploadDelaySeconds = maxUploadDelaySeconds
        self.enableDifferentialPrivacy = enableDifferentialPrivacy
        self.dpEpsilon = dpEpsilon
        self.dpClippingNorm = dpClippingNorm
    }

    /// Default privacy configuration (staggered updates enabled, DP disabled).
    public static let standard = PrivacyConfiguration()

    /// High privacy configuration (staggered updates + differential privacy).
    public static let highPrivacy = PrivacyConfiguration(
        enableStaggeredUpdates: true,
        minUploadDelaySeconds: 60,
        maxUploadDelaySeconds: 600,
        enableDifferentialPrivacy: true,
        dpEpsilon: 0.5,
        dpClippingNorm: 1.0
    )

    /// No privacy enhancements (for testing/debugging).
    public static let disabled = PrivacyConfiguration(
        enableStaggeredUpdates: false,
        minUploadDelaySeconds: 0,
        maxUploadDelaySeconds: 0,
        enableDifferentialPrivacy: false
    )

    /// Compute a random upload delay based on configuration.
    /// - Returns: Random delay in seconds
    public func randomUploadDelay() -> Double {
        guard enableStaggeredUpdates else { return 0.0 }

        let range = maxUploadDelaySeconds - minUploadDelaySeconds
        let randomValue = Double.random(in: 0...1)
        return minUploadDelaySeconds + (randomValue * range)
    }
}
