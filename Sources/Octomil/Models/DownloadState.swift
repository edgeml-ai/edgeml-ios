import Foundation

/// Progress information for a model download.
public struct DownloadProgress: Sendable {
    /// Model identifier.
    public let modelId: String
    /// Model version being downloaded.
    public let version: String
    /// Bytes downloaded so far.
    public let bytesDownloaded: Int64
    /// Total bytes to download.
    public let totalBytes: Int64
    /// Download progress (0.0 to 1.0).
    public var progress: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(bytesDownloaded) / Double(totalBytes)
    }

    public init(
        modelId: String,
        version: String,
        bytesDownloaded: Int64,
        totalBytes: Int64
    ) {
        self.modelId = modelId
        self.version = version
        self.bytesDownloaded = bytesDownloaded
        self.totalBytes = totalBytes
    }
}

/// Represents the current state of a model download operation.
public enum DownloadState: Sendable {
    /// No download in progress.
    case idle
    /// Checking the server for available updates.
    case checkingForUpdates
    /// Downloading model data.
    case downloading(DownloadProgress)
    /// Verifying downloaded model integrity.
    case verifying
    /// Download and verification completed successfully.
    case completed
    /// Download or verification failed.
    case failed
    /// Model is already up to date.
    case upToDate
}
