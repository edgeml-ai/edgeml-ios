import Foundation
import CoreML

/// Unified model deployment API.
///
/// Loads a model from a local URL, auto-detects the engine, and returns
/// a `DeployedModel` ready for inference.
public enum Deploy {

    /// Deploy a model from a local file URL.
    ///
    /// - Parameters:
    ///   - url: Path to the model file (`.mlmodelc`, `.mlmodel`, or `.mlpackage`).
    ///   - engine: Inference engine to use. Defaults to `.auto` (CoreML on iOS).
    ///   - name: Human-readable name. Defaults to the filename without extension.
    /// - Returns: A `DeployedModel` ready for inference.
    /// - Throws: If the model cannot be loaded.
    public static func model(
        at url: URL,
        engine: Engine = .auto,
        name: String? = nil
    ) throws -> DeployedModel {
        let resolvedName = name ?? url.deletingPathExtension().lastPathComponent
        let resolvedEngine = resolveEngine(engine: engine)

        let mlModel: MLModel
        let compiledURL: URL

        let ext = url.pathExtension.lowercased()
        switch ext {
        case "mlmodelc":
            // Already compiled
            mlModel = try MLModel(contentsOf: url)
            compiledURL = url
        case "mlmodel", "mlpackage":
            // Compile first
            let compiled = try MLModel.compileModel(at: url)
            mlModel = try MLModel(contentsOf: compiled)
            compiledURL = compiled
        default:
            throw DeployError.unsupportedFormat(ext)
        }

        let metadata = ModelMetadata(
            modelId: resolvedName,
            version: "local",
            checksum: "",
            fileSize: 0,
            createdAt: Date(),
            format: resolvedEngine.rawValue,
            supportsTraining: mlModel.modelDescription.isUpdatable,
            description: "Locally deployed model",
            inputSchema: nil,
            outputSchema: nil
        )

        let edgeMLModel = EdgeMLModel(
            id: resolvedName,
            version: "local",
            mlModel: mlModel,
            metadata: metadata,
            compiledModelURL: compiledURL
        )

        return DeployedModel(name: resolvedName, engine: resolvedEngine, model: edgeMLModel)
    }

    private static func resolveEngine(engine: Engine) -> Engine {
        switch engine {
        case .auto:
            return .coreml  // CoreML is the only engine on iOS
        case .coreml:
            return .coreml
        }
    }
}

/// Errors from the deploy API.
public enum DeployError: Error, LocalizedError {
    case unsupportedFormat(String)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "Unsupported model format: .\(ext). Supported formats: .mlmodelc, .mlmodel, .mlpackage"
        }
    }
}
