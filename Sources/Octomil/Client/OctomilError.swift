import Foundation

/// Errors that can occur during Octomil SDK operations.
public enum OctomilError: LocalizedError, Sendable {

    // MARK: - Network Errors

    /// Network is not available.
    case networkUnavailable

    /// Request timed out.
    case requestTimeout

    /// Server returned an error response.
    case serverError(statusCode: Int, message: String)

    /// Failed to decode server response.
    case decodingError(underlying: String)

    /// Invalid URL or request configuration.
    case invalidRequest(reason: String)

    // MARK: - Authentication Errors

    /// API key is invalid or expired.
    case invalidAPIKey

    /// Device is not registered.
    case deviceNotRegistered

    /// Authentication failed.
    case authenticationFailed(reason: String)

    // MARK: - Model Errors

    /// Model with specified ID was not found.
    case modelNotFound(modelId: String)

    /// Model version was not found.
    case versionNotFound(modelId: String, version: String)

    /// Model download failed.
    case downloadFailed(reason: String)

    /// Checksum verification failed after download.
    case checksumMismatch

    /// Failed to compile CoreML model.
    case modelCompilationFailed(reason: String)

    /// Model format is not supported.
    case unsupportedModelFormat(format: String)

    // MARK: - Cache Errors

    /// Cache operation failed.
    case cacheError(reason: String)

    /// Insufficient storage space.
    case insufficientStorage

    // MARK: - Training Errors

    /// Training failed.
    case trainingFailed(reason: String)

    /// Model does not support on-device training.
    case trainingNotSupported

    /// Weight extraction failed.
    case weightExtractionFailed(reason: String)

    /// Weight upload failed.
    case uploadFailed(reason: String)

    // MARK: - Keychain Errors

    /// Keychain operation failed.
    case keychainError(status: OSStatus)

    // MARK: - General Errors

    /// An unexpected error occurred.
    case unknown(underlying: Error?)

    /// Operation was cancelled.
    case cancelled

    // MARK: - LocalizedError

    public var errorDescription: String? {
        switch self {
        case .networkUnavailable:
            return "Network is not available. Please check your connection."
        case .requestTimeout:
            return "Request timed out. Please try again."
        case .serverError(let statusCode, let message):
            return "Server error (\(statusCode)): \(message)"
        case .decodingError(let underlying):
            return "Failed to decode response: \(underlying)"
        case .invalidRequest(let reason):
            return "Invalid request: \(reason)"
        case .invalidAPIKey:
            return "API key is invalid or expired."
        case .deviceNotRegistered:
            return "Device is not registered. Please call register() first."
        case .authenticationFailed(let reason):
            return "Authentication failed: \(reason)"
        case .modelNotFound(let modelId):
            return "Model not found: \(modelId)"
        case .versionNotFound(let modelId, let version):
            return "Version \(version) not found for model \(modelId)"
        case .downloadFailed(let reason):
            return "Model download failed: \(reason)"
        case .checksumMismatch:
            return "Downloaded model checksum does not match. File may be corrupted."
        case .modelCompilationFailed(let reason):
            return "Failed to compile CoreML model: \(reason)"
        case .unsupportedModelFormat(let format):
            return "Model format '\(format)' is not supported on iOS."
        case .cacheError(let reason):
            return "Cache error: \(reason)"
        case .insufficientStorage:
            return "Insufficient storage space for model."
        case .trainingFailed(let reason):
            return "Training failed: \(reason)"
        case .trainingNotSupported:
            return "This model does not support on-device training."
        case .weightExtractionFailed(let reason):
            return "Failed to extract model weights: \(reason)"
        case .uploadFailed(let reason):
            return "Failed to upload weights: \(reason)"
        case .keychainError(let status):
            return "Keychain error (status: \(status))"
        case .unknown(let underlying):
            if let error = underlying {
                return "An unexpected error occurred: \(error.localizedDescription)"
            }
            return "An unexpected error occurred."
        case .cancelled:
            return "Operation was cancelled."
        }
    }

    public var failureReason: String? {
        errorDescription
    }

    public var recoverySuggestion: String? {
        switch self {
        case .networkUnavailable:
            return "Check your network connection and try again."
        case .requestTimeout:
            return "Ensure you have a stable connection and try again."
        case .serverError:
            return "Try again later. If the problem persists, contact support."
        case .invalidAPIKey:
            return "Verify your API key is correct and not expired."
        case .deviceNotRegistered:
            return "Call client.register() to register the device."
        case .checksumMismatch:
            return "Try downloading the model again."
        case .insufficientStorage:
            return "Free up storage space on the device."
        case .trainingNotSupported:
            return "Use a model that supports on-device training."
        default:
            return nil
        }
    }
}
