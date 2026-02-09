import Foundation
import CoreML
import os.log
import CryptoKit

/// Manages model download, caching, and version control.
public actor ModelManager {

    // MARK: - Properties

    private let apiClient: APIClient
    private let modelCache: ModelCache
    private let configuration: EdgeMLConfiguration
    private let logger: Logger
    private let fileManager = FileManager.default

    private var downloadTasks: [String: Task<EdgeMLModel, Error>] = [:]

    // MARK: - Initialization

    /// Creates a new model manager.
    /// - Parameters:
    ///   - apiClient: API client for server communication.
    ///   - configuration: SDK configuration.
    internal init(apiClient: APIClient, configuration: EdgeMLConfiguration) {
        self.apiClient = apiClient
        self.configuration = configuration
        self.modelCache = ModelCache(maxSize: configuration.maxCacheSize)
        self.logger = Logger(subsystem: "ai.edgeml.sdk", category: "ModelManager")
    }

    // MARK: - Download

    /// Downloads a model from the server.
    ///
    /// If a download is already in progress for this model, returns the existing task.
    ///
    /// - Parameters:
    ///   - modelId: Model identifier.
    ///   - version: Model version.
    /// - Returns: Downloaded model.
    /// - Throws: `EdgeMLError` if download fails.
    public func downloadModel(modelId: String, version: String) async throws -> EdgeMLModel {
        let cacheKey = "\(modelId)_\(version)"

        // Check if already downloading
        if let existingTask = downloadTasks[cacheKey] {
            return try await existingTask.value
        }

        // Check cache first
        if let cached = modelCache.get(modelId: modelId, version: version) {
            if configuration.enableLogging {
                logger.debug("Model found in cache: \(modelId)@\(version)")
            }
            return cached
        }

        // Start download task
        let task = Task<EdgeMLModel, Error> {
            defer {
                Task { await self.removeDownloadTask(cacheKey) }
            }

            let metadata = try await apiClient.getModelMetadata(modelId: modelId, version: version)
            let modelData = try await fetchAndVerifyModelData(modelId: modelId, version: version)
            let model = try await compileAndCacheModel(
                modelId: modelId, version: version, modelData: modelData, metadata: metadata
            )

            if self.configuration.enableLogging {
                self.logger.info("Model downloaded: \(modelId)@\(version)")
            }

            return model
        }

        downloadTasks[cacheKey] = task
        return try await task.value
    }

    private func removeDownloadTask(_ key: String) {
        downloadTasks[key] = nil
    }

    // MARK: - Cache Access

    /// Gets a cached model.
    /// - Parameters:
    ///   - modelId: Model identifier.
    ///   - version: Optional version. Returns latest cached if nil.
    /// - Returns: Cached model or nil if not found.
    public nonisolated func getCachedModel(modelId: String) -> EdgeMLModel? {
        return modelCache.getLatest(modelId: modelId)
    }

    /// Gets a cached model with specific version.
    public nonisolated func getCachedModel(modelId: String, version: String) -> EdgeMLModel? {
        return modelCache.get(modelId: modelId, version: version)
    }

    /// Clears all cached models.
    public func clearCache() throws {
        try modelCache.clearAll()
    }

    /// Gets the size of the cache in bytes.
    public nonisolated func getCacheSize() -> UInt64 {
        return modelCache.currentSize
    }

    // MARK: - Private Helpers

    private func fetchAndVerifyModelData(modelId: String, version: String) async throws -> Data {
        let downloadInfo = try await apiClient.getDownloadURL(
            modelId: modelId,
            version: version,
            format: "coreml"
        )

        guard let downloadURL = URL(string: downloadInfo.url) else {
            throw EdgeMLError.invalidRequest(reason: "Invalid download URL")
        }

        let modelData = try await apiClient.downloadData(from: downloadURL)

        // Verify checksum
        let checksum = SHA256.hash(data: modelData).compactMap { String(format: "%02x", $0) }.joined()
        guard checksum == downloadInfo.checksum else {
            throw EdgeMLError.checksumMismatch
        }

        return modelData
    }

    private func compileAndCacheModel(
        modelId: String,
        version: String,
        modelData: Data,
        metadata: ModelMetadata
    ) async throws -> EdgeMLModel {
        // Save to temporary file
        let tempFile = fileManager.temporaryDirectory
            .appendingPathComponent("\(modelId)_\(version).mlmodel")
        try modelData.write(to: tempFile)

        defer { try? fileManager.removeItem(at: tempFile) }

        // Compile model
        let compiledURL: URL
        do {
            compiledURL = try MLModel.compileModel(at: tempFile)
        } catch {
            throw EdgeMLError.modelCompilationFailed(reason: error.localizedDescription)
        }

        // Move to cache directory
        let cacheURL = try await modelCache.cacheCompiledModel(
            modelId: modelId,
            version: version,
            compiledURL: compiledURL
        )

        // Load model
        let mlModel: MLModel
        do {
            mlModel = try MLModel(contentsOf: cacheURL)
        } catch {
            throw EdgeMLError.modelCompilationFailed(reason: error.localizedDescription)
        }

        let model = EdgeMLModel(
            id: modelId,
            version: version,
            mlModel: mlModel,
            metadata: metadata,
            compiledModelURL: cacheURL
        )

        await modelCache.store(model)

        return model
    }
}
