import Foundation

/// Represents the current state of the EdgeML client lifecycle.
public enum ClientState: String, Sendable {
    /// Client created but not initialized.
    case uninitialized
    /// Initialization in progress (registering device, loading model).
    case initializing
    /// Ready for operations (inference, training, etc.).
    case ready
    /// An error occurred during initialization or operation.
    case error
    /// Client has been closed and resources released.
    case closed
}
