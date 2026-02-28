import Foundation
import MLX
import MLXNN
import MLXLLM
import MLXLMCommon
import Octomil

/// Real MLX-backed LLM inference engine conforming to ``StreamingInferenceEngine``.
///
/// Uses `mlx-swift-lm`'s ``ModelContainer`` for token-by-token generation on Apple Silicon.
/// Supports KV cache prefix reuse across sequential generations sharing a common prompt prefix.
/// Requires iOS 17+ / macOS 14+.
@available(iOS 17.0, macOS 14.0, *)
public final class MLXLLMEngine: StreamingInferenceEngine, @unchecked Sendable {

    private let modelContainer: ModelContainer
    public var maxTokens: Int
    public var temperature: Float
    public let cacheEnabled: Bool

    // KV cache state — guarded by modelContainer.perform serialization
    private var lastPromptTokens: [Int]?
    private var lastKVCache: [KVCache]?
    private var _cacheHits: Int = 0
    private var _cacheMisses: Int = 0

    /// Number of KV cache hits since engine creation.
    public var cacheHits: Int { _cacheHits }
    /// Number of KV cache misses since engine creation.
    public var cacheMisses: Int { _cacheMisses }

    /// Creates an MLX LLM engine.
    /// - Parameters:
    ///   - modelContainer: A loaded MLX model container.
    ///   - maxTokens: Maximum tokens to generate (default: 512).
    ///   - temperature: Sampling temperature (default: 0.7).
    ///   - cacheEnabled: Whether to reuse KV caches across generations (default: true).
    public init(
        modelContainer: ModelContainer,
        maxTokens: Int = 512,
        temperature: Float = 0.7,
        cacheEnabled: Bool = true
    ) {
        self.modelContainer = modelContainer
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.cacheEnabled = cacheEnabled
    }

    // MARK: - StreamingInferenceEngine

    public func generate(input: Any, modality: Modality) -> AsyncThrowingStream<InferenceChunk, Error> {
        let prompt: String
        if let str = input as? String {
            prompt = str
        } else {
            prompt = String(describing: input)
        }

        let maxTokens = self.maxTokens
        let temperature = self.temperature
        let container = self.modelContainer
        let cacheEnabled = self.cacheEnabled

        return AsyncThrowingStream { continuation in
            let task = Task { [weak self] in
                do {
                    var index = 0

                    let result = try await container.perform { context in
                        let prepared = try await context.processor.prepare(input: .init(prompt: prompt))

                        // Tokenize to get prompt token IDs for cache matching
                        let promptTokenIds = context.tokenizer.encode(text: prompt)

                        // Fetch or create KV cache
                        let cache: [KVCache]? = cacheEnabled
                            ? self?.fetchOrCreateCache(promptTokenIds: promptTokenIds, context: context)
                            : nil

                        return try MLXLMCommon.generate(
                            input: prepared,
                            parameters: .init(temperature: temperature, topP: 0.9, prefillStepSize: 4096),
                            context: context,
                            cache: cache
                        ) { tokens in
                            if Task.isCancelled {
                                return .stop
                            }

                            let tokenCount = tokens.count
                            if tokenCount > index {
                                let newText = context.tokenizer.decode(tokens: Array(tokens[index...]))
                                let data = Data(newText.utf8)
                                let chunk = InferenceChunk(
                                    index: index,
                                    data: data,
                                    modality: .text,
                                    timestamp: Date(),
                                    latencyMs: 0
                                )
                                continuation.yield(chunk)
                                index = tokenCount
                            }

                            if tokenCount >= maxTokens {
                                return .stop
                            }

                            return .more
                        }
                    }

                    // Store cache for next generation
                    if cacheEnabled {
                        let promptTokenIds = await container.perform { context in
                            context.tokenizer.encode(text: prompt)
                        }
                        self?.storeCache(promptTokenIds: promptTokenIds, cache: result.cache)
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    // MARK: - KV Cache Management

    /// Find the longest common prefix between current prompt tokens and last cached tokens.
    /// If commonLen >= 4, reuse the cache with trimming. Otherwise, create fresh caches.
    private func fetchOrCreateCache(promptTokenIds: [Int], context: ModelContext) -> [KVCache]? {
        guard let lastTokens = lastPromptTokens, let cachedKV = lastKVCache else {
            _cacheMisses += 1
            return nil
        }

        let commonLen = zip(promptTokenIds, lastTokens).prefix(while: { $0 == $1 }).count

        guard commonLen >= 4 else {
            _cacheMisses += 1
            lastKVCache = nil
            lastPromptTokens = nil
            return nil
        }

        // Trim cache to common prefix length minus 1 (re-process last common token)
        let trimTarget = commonLen - 1
        for kv in cachedKV {
            if kv.isTrimmable {
                kv.trim(to: trimTarget)
            }
        }

        _cacheHits += 1
        return cachedKV
    }

    /// Store the KV cache and prompt tokens for potential reuse in the next generation.
    private func storeCache(promptTokenIds: [Int], cache: [KVCache]?) {
        lastPromptTokens = promptTokenIds
        lastKVCache = cache
    }
}
