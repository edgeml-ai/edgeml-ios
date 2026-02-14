import Foundation

// MARK: - Tensor Info

/// Information about a model's input and output tensors.
public struct TensorInfo: Sendable {
    /// Expected input tensor shape (e.g., [1, 28, 28, 1] for MNIST).
    public let inputShape: [Int]

    /// Expected output tensor shape (e.g., [1, 10] for 10-class classifier).
    public let outputShape: [Int]

    /// Input tensor data type (e.g., "FLOAT32", "MultiArray").
    public let inputType: String

    /// Output tensor data type (e.g., "FLOAT32", "MultiArray").
    public let outputType: String

    public init(inputShape: [Int], outputShape: [Int], inputType: String, outputType: String) {
        self.inputShape = inputShape
        self.outputShape = outputShape
        self.inputType = inputType
        self.outputType = outputType
    }
}

// MARK: - Model Info

/// Summary information about a loaded model.
public struct ModelInfo: Sendable {
    /// Model identifier.
    public let modelId: String

    /// Model version.
    public let version: String

    /// Model format (e.g., "coreml", "tflite").
    public let format: String

    /// Model file size in bytes.
    public let sizeBytes: Int64

    /// Expected input tensor shape.
    public let inputShape: [Int]

    /// Expected output tensor shape.
    public let outputShape: [Int]

    /// Whether the model is using the Neural Engine.
    public let usingNeuralEngine: Bool

    public init(
        modelId: String,
        version: String,
        format: String,
        sizeBytes: Int64,
        inputShape: [Int],
        outputShape: [Int],
        usingNeuralEngine: Bool
    ) {
        self.modelId = modelId
        self.version = version
        self.format = format
        self.sizeBytes = sizeBytes
        self.inputShape = inputShape
        self.outputShape = outputShape
        self.usingNeuralEngine = usingNeuralEngine
    }
}

// MARK: - Model Contract

/// Describes the input/output contract of a loaded model.
///
/// Use this at initialization time to validate that your data pipeline
/// produces tensors with the correct shape and type. This catches
/// mismatches early rather than at inference time.
///
/// ```swift
/// let contract = client.getModelContract()!
///
/// // Check input compatibility
/// let myInput = [Float](repeating: 0, count: 784)
/// guard contract.validateInput(myInput) else {
///     fatalError("Bad input: \(contract.inputDescription)")
/// }
///
/// // Check training support
/// if !contract.hasTrainingSignature {
///     print("Model does not support on-device training")
/// }
/// ```
public struct ModelContract: Sendable {
    /// Model identifier.
    public let modelId: String

    /// Model version.
    public let version: String

    /// Expected input tensor shape (e.g., [1, 28, 28, 1] for MNIST).
    public let inputShape: [Int]

    /// Expected output tensor shape (e.g., [1, 10] for 10-class classifier).
    public let outputShape: [Int]

    /// Input tensor data type (e.g., "FLOAT32", "MultiArray").
    public let inputType: String

    /// Output tensor data type (e.g., "FLOAT32", "MultiArray").
    public let outputType: String

    /// Whether the model supports on-device gradient-based training.
    public let hasTrainingSignature: Bool

    /// Available signature or capability keys (e.g., ["train", "infer", "save"]).
    public let signatureKeys: [String]

    public init(
        modelId: String,
        version: String,
        inputShape: [Int],
        outputShape: [Int],
        inputType: String,
        outputType: String,
        hasTrainingSignature: Bool,
        signatureKeys: [String]
    ) {
        self.modelId = modelId
        self.version = version
        self.inputShape = inputShape
        self.outputShape = outputShape
        self.inputType = inputType
        self.outputType = outputType
        self.hasTrainingSignature = hasTrainingSignature
        self.signatureKeys = signatureKeys
    }

    /// Total number of input elements expected (product of input shape dimensions).
    public var inputSize: Int {
        inputShape.reduce(1, *)
    }

    /// Total number of output elements produced (product of output shape dimensions).
    public var outputSize: Int {
        outputShape.reduce(1, *)
    }

    /// Human-readable description of expected input
    /// (e.g., "[Float][784] shape=[1, 28, 28, 1] type=FLOAT32").
    public var inputDescription: String {
        "[Float][\(inputSize)] shape=\(inputShape) type=\(inputType)"
    }

    /// Validate that a float array is compatible with this model's input.
    ///
    /// - Parameter input: The data to validate.
    /// - Returns: `true` if the input count matches the model's expected input size.
    public func validateInput(_ input: [Float]) -> Bool {
        input.count == inputSize
    }

    /// Validate that a float array is compatible with this model's input,
    /// throwing a descriptive error if not.
    ///
    /// - Parameter input: The data to validate.
    /// - Throws: An error if the input size doesn't match.
    public func requireValidInput(_ input: [Float]) throws {
        guard input.count == inputSize else {
            throw ModelContractValidationError(
                actual: input.count,
                expected: inputSize,
                inputDescription: inputDescription
            )
        }
    }
}

/// Error thrown when model input validation fails.
public struct ModelContractValidationError: LocalizedError, Sendable {
    public let actual: Int
    public let expected: Int
    public let inputDescription: String

    public var errorDescription: String? {
        "Input size mismatch: got \(actual) elements, expected \(inputDescription)"
    }
}
