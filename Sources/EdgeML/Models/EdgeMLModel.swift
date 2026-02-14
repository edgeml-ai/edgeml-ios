import Foundation
import CoreML
import os.log

/// Represents a machine learning model loaded in the EdgeML SDK.
///
/// `EdgeMLModel` wraps a CoreML model and provides:
/// - Model metadata (ID, version, checksum)
/// - Inference capabilities
/// - Training support detection
public final class EdgeMLModel: @unchecked Sendable {

    // MARK: - Properties

    /// The unique model identifier.
    public let id: String

    /// The model version.
    public let version: String

    /// The underlying CoreML model.
    public let mlModel: MLModel

    /// Model metadata from the server.
    public let metadata: ModelMetadata

    /// URL of the compiled model.
    public let compiledModelURL: URL

    /// Whether this model supports on-device training.
    public var supportsTraining: Bool {
        return metadata.supportsTraining && mlModel.modelDescription.isUpdatable
    }

    /// Model description from CoreML.
    public var modelDescription: MLModelDescription {
        return mlModel.modelDescription
    }

    /// Input feature descriptions.
    public var inputDescriptions: [String: MLFeatureDescription] {
        var descriptions: [String: MLFeatureDescription] = [:]
        for (name, description) in mlModel.modelDescription.inputDescriptionsByName {
            descriptions[name] = description
        }
        return descriptions
    }

    /// Output feature descriptions.
    public var outputDescriptions: [String: MLFeatureDescription] {
        var descriptions: [String: MLFeatureDescription] = [:]
        for (name, description) in mlModel.modelDescription.outputDescriptionsByName {
            descriptions[name] = description
        }
        return descriptions
    }

    /// Optional MNN runtime configuration for the model.
    public var mnnConfig: [String: Any]? = nil

    private let logger: Logger

    // MARK: - Initialization

    /// Creates a new EdgeMLModel.
    /// - Parameters:
    ///   - id: Model identifier.
    ///   - version: Model version.
    ///   - mlModel: CoreML model.
    ///   - metadata: Model metadata.
    ///   - compiledModelURL: URL of the compiled model.
    internal init(
        id: String,
        version: String,
        mlModel: MLModel,
        metadata: ModelMetadata,
        compiledModelURL: URL
    ) {
        self.id = id
        self.version = version
        self.mlModel = mlModel
        self.metadata = metadata
        self.compiledModelURL = compiledModelURL
        self.logger = Logger(subsystem: "ai.edgeml.sdk", category: "EdgeMLModel")
    }

    // MARK: - Local-First Initialization

    /// Creates an EdgeMLModel from a pre-compiled CoreML model bundle (`.mlmodelc`).
    ///
    /// Use this initializer for local-first inference without any server dependency:
    /// ```swift
    /// let model = try EdgeMLModel(
    ///     compiledModelURL: Bundle.main.url(forResource: "classifier", withExtension: "mlmodelc")!
    /// )
    /// let result = try model.predict(input: features)
    /// ```
    ///
    /// To upgrade to the server platform later (FL, analytics, etc.), pass the
    /// locally-created model to `EdgeMLClient` methods — they accept any `EdgeMLModel`.
    ///
    /// - Parameters:
    ///   - compiledModelURL: URL to a compiled `.mlmodelc` bundle.
    ///   - configuration: CoreML model configuration (compute units, etc.).
    /// - Throws: `EdgeMLError.localModelNotFound` if the URL doesn't exist,
    ///           or a CoreML error if the model can't be loaded.
    public convenience init(
        compiledModelURL: URL,
        configuration: MLModelConfiguration = MLModelConfiguration()
    ) throws {
        guard FileManager.default.fileExists(atPath: compiledModelURL.path) else {
            throw EdgeMLError.localModelNotFound(path: compiledModelURL.path)
        }
        let mlModel = try MLModel(contentsOf: compiledModelURL, configuration: configuration)
        let name = compiledModelURL.deletingPathExtension().lastPathComponent
        let metadata = ModelMetadata(
            modelId: name,
            version: "local",
            checksum: "",
            fileSize: 0,
            createdAt: Date(),
            format: "coreml",
            supportsTraining: mlModel.modelDescription.isUpdatable,
            description: nil,
            inputSchema: nil,
            outputSchema: nil
        )
        self.init(id: name, version: "local", mlModel: mlModel,
                  metadata: metadata, compiledModelURL: compiledModelURL)
    }

    /// Creates an EdgeMLModel from an uncompiled CoreML model (`.mlmodel` or `.mlpackage`).
    ///
    /// The model is compiled at load time using `MLModel.compileModel(at:)`.
    /// For production apps, prefer the `compiledModelURL:` initializer with a
    /// pre-compiled `.mlmodelc` bundle for faster startup.
    ///
    /// - Parameters:
    ///   - modelURL: URL to an `.mlmodel` or `.mlpackage` file.
    ///   - configuration: CoreML model configuration (compute units, etc.).
    /// - Throws: `EdgeMLError.localModelNotFound` if the URL doesn't exist,
    ///           `EdgeMLError.modelCompilationFailed` if compilation fails,
    ///           or a CoreML error if the compiled model can't be loaded.
    public convenience init(
        modelURL: URL,
        configuration: MLModelConfiguration = MLModelConfiguration()
    ) throws {
        guard FileManager.default.fileExists(atPath: modelURL.path) else {
            throw EdgeMLError.localModelNotFound(path: modelURL.path)
        }
        let compiledURL: URL
        do {
            compiledURL = try MLModel.compileModel(at: modelURL)
        } catch {
            throw EdgeMLError.modelCompilationFailed(reason: error.localizedDescription)
        }
        try self.init(compiledModelURL: compiledURL, configuration: configuration)
    }

    // MARK: - Inference

    /// Makes a prediction with the model.
    ///
    /// - Parameter input: Input features for prediction.
    /// - Returns: Model prediction output.
    /// - Throws: Error if prediction fails.
    public func predict(input: MLFeatureProvider) throws -> MLFeatureProvider {
        return try mlModel.prediction(from: input)
    }

    /// Makes a prediction with the model using specified options.
    ///
    /// - Parameters:
    ///   - input: Input features for prediction.
    ///   - options: Prediction options.
    /// - Returns: Model prediction output.
    /// - Throws: Error if prediction fails.
    public func predict(input: MLFeatureProvider, options: MLPredictionOptions) throws -> MLFeatureProvider {
        return try mlModel.prediction(from: input, options: options)
    }

    /// Makes batch predictions with the model.
    ///
    /// - Parameter inputBatch: Batch of input features.
    /// - Returns: Batch of predictions.
    /// - Throws: Error if prediction fails.
    public func predict(batch inputBatch: MLBatchProvider) throws -> MLBatchProvider {
        return try mlModel.predictions(from: inputBatch, options: MLPredictionOptions())
    }

    /// Makes a prediction with the model using a dictionary of inputs.
    ///
    /// - Parameter inputs: Dictionary of feature name to value.
    /// - Returns: Model prediction output.
    /// - Throws: Error if prediction fails.
    public func predict(inputs: [String: Any]) throws -> MLFeatureProvider {
        let featureProvider = try MLDictionaryFeatureProvider(dictionary: inputs)
        return try mlModel.prediction(from: featureProvider)
    }

    // MARK: - Async Inference

    /// Makes a prediction with the model asynchronously.
    ///
    /// - Parameter input: Input features for prediction.
    /// - Returns: Model prediction output.
    /// - Throws: Error if prediction fails.
    @available(iOS 15.0, macOS 12.0, *)
    public func predictAsync(input: MLFeatureProvider) async throws -> MLFeatureProvider {
        return try await withCheckedThrowingContinuation { continuation in
            do {
                let result = try mlModel.prediction(from: input)
                continuation.resume(returning: result)
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Streaming Inference

    /// Streams generative inference output chunk-by-chunk.
    ///
    /// The returned ``AsyncThrowingStream`` yields ``InferenceChunk`` values
    /// with per-chunk timing instrumentation.  After the stream completes,
    /// call the companion `result` closure to obtain aggregated metrics.
    ///
    /// - Parameters:
    ///   - input: Modality-specific input (e.g. a prompt string for text).
    ///   - modality: The generation modality.
    ///   - engine: A ``StreamingInferenceEngine`` (defaults to ``LLMEngine`` for text).
    /// - Returns: An ``AsyncThrowingStream`` of ``InferenceChunk``.
    public func generateStream(
        input: Any,
        modality: Modality,
        engine: StreamingInferenceEngine? = nil
    ) -> (stream: AsyncThrowingStream<InferenceChunk, Error>, result: @Sendable () -> StreamingInferenceResult?) {
        let resolvedEngine: StreamingInferenceEngine
        if let engine = engine {
            resolvedEngine = engine
        } else {
            switch modality {
            case .text:
                resolvedEngine = LLMEngine(modelPath: compiledModelURL)
            case .image:
                resolvedEngine = ImageEngine(modelPath: compiledModelURL)
            case .audio:
                resolvedEngine = AudioEngine(modelPath: compiledModelURL)
            case .video:
                resolvedEngine = VideoEngine(modelPath: compiledModelURL)
            }
        }

        let wrapper = InstrumentedStreamWrapper(modality: modality)
        return wrapper.wrap(resolvedEngine, input: input)
    }
}

// MARK: - Equatable

extension EdgeMLModel: Equatable {
    public static func == (lhs: EdgeMLModel, rhs: EdgeMLModel) -> Bool {
        return lhs.id == rhs.id && lhs.version == rhs.version
    }
}

// MARK: - Hashable

extension EdgeMLModel: Hashable {
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(version)
    }
}

// MARK: - CustomStringConvertible

extension EdgeMLModel: CustomStringConvertible {
    public var description: String {
        return "EdgeMLModel(id: \(id), version: \(version), supportsTraining: \(supportsTraining))"
    }
}
