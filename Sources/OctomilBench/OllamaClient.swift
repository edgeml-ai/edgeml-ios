import Foundation

/// Lightweight REST client for Ollama HTTP API.
public actor OllamaClient {
    private let baseURL: URL
    private let session: URLSession

    public init(host: String = "http://localhost:11434") {
        self.baseURL = URL(string: host)!
        self.session = URLSession(configuration: .ephemeral)
    }

    // MARK: - Health Check

    public func isAvailable() async -> Bool {
        var request = URLRequest(url: baseURL)
        request.timeoutInterval = 5
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - List Models

    public struct OllamaModel: Codable, Sendable {
        public let name: String
        public let size: Int64?
    }

    private struct ListResponse: Codable {
        let models: [OllamaModel]
    }

    public func listModels() async throws -> [OllamaModel] {
        let url = baseURL.appendingPathComponent("api/tags")
        let (data, _) = try await session.data(from: url)
        return try JSONDecoder().decode(ListResponse.self, from: data).models
    }

    public func hasModel(_ id: String) async throws -> Bool {
        let models = try await listModels()
        return models.contains { $0.name.hasPrefix(id) || id.hasPrefix($0.name) }
    }

    // MARK: - Pull Model

    public func pullModel(_ id: String) async throws {
        let url = baseURL.appendingPathComponent("api/pull")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["name": id])
        request.timeoutInterval = 600  // models can be large

        let (bytes, _) = try await session.bytes(for: request)
        // Consume the stream to completion (Ollama streams pull progress)
        for try await _ in bytes.lines {}
    }

    // MARK: - Generate (non-streaming)

    public struct GenerateResponse: Codable, Sendable {
        public let model: String
        public let response: String
        public let totalDuration: Int64?         // nanoseconds
        public let loadDuration: Int64?          // nanoseconds
        public let promptEvalCount: Int?
        public let promptEvalDuration: Int64?    // nanoseconds
        public let evalCount: Int?
        public let evalDuration: Int64?          // nanoseconds

        enum CodingKeys: String, CodingKey {
            case model, response
            case totalDuration = "total_duration"
            case loadDuration = "load_duration"
            case promptEvalCount = "prompt_eval_count"
            case promptEvalDuration = "prompt_eval_duration"
            case evalCount = "eval_count"
            case evalDuration = "eval_duration"
        }
    }

    public func generate(
        model: String,
        prompt: String,
        maxTokens: Int = 128,
        temperature: Double = 0.0,
        topP: Double = 0.9
    ) async throws -> GenerateResponse {
        let url = baseURL.appendingPathComponent("api/generate")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 300

        let body: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false,
            "options": [
                "num_predict": maxTokens,
                "temperature": temperature,
                "top_p": topP,
            ] as [String: Any],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, httpResponse) = try await session.data(for: request)
        guard let status = (httpResponse as? HTTPURLResponse)?.statusCode, status == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "unknown"
            throw OllamaError.requestFailed(status: (httpResponse as? HTTPURLResponse)?.statusCode ?? 0, body: body)
        }
        return try JSONDecoder().decode(GenerateResponse.self, from: data)
    }

    public enum OllamaError: Error, LocalizedError {
        case requestFailed(status: Int, body: String)
        case modelNotFound(String)

        public var errorDescription: String? {
            switch self {
            case .requestFailed(let status, let body):
                return "Ollama request failed (HTTP \(status)): \(body.prefix(200))"
            case .modelNotFound(let id):
                return "Ollama model not found: \(id)"
            }
        }
    }
}
