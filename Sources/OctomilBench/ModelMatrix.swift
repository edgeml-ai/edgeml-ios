import Foundation

/// Model specification mapping MLX Hub IDs to Ollama IDs.
public struct ModelSpec: Codable, Sendable, Hashable {
    public let name: String
    public let mlxId: String
    public let ollamaId: String
    public let params: String

    public init(name: String, mlxId: String, ollamaId: String, params: String) {
        self.name = name
        self.mlxId = mlxId
        self.ollamaId = ollamaId
        self.params = params
    }
}

/// All benchmark models.
public enum ModelMatrix {
    public static let all: [ModelSpec] = [
        ModelSpec(
            name: "Llama 3.2 1B",
            mlxId: "mlx-community/Llama-3.2-1B-Instruct-4bit",
            ollamaId: "llama3.2:1b",
            params: "1B"
        ),
        ModelSpec(
            name: "Llama 3.2 3B",
            mlxId: "mlx-community/Llama-3.2-3B-Instruct-4bit",
            ollamaId: "llama3.2:3b",
            params: "3B"
        ),
        ModelSpec(
            name: "Qwen 2.5 0.5B",
            mlxId: "mlx-community/Qwen2.5-0.5B-Instruct-4bit",
            ollamaId: "qwen2.5:0.5b",
            params: "0.5B"
        ),
        ModelSpec(
            name: "Qwen 2.5 1.5B",
            mlxId: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
            ollamaId: "qwen2.5:1.5b",
            params: "1.5B"
        ),
        ModelSpec(
            name: "Gemma 2 2B",
            mlxId: "mlx-community/gemma-2-2b-it-4bit",
            ollamaId: "gemma2:2b",
            params: "2B"
        ),
        ModelSpec(
            name: "Phi-3.5 Mini",
            mlxId: "mlx-community/Phi-3.5-mini-instruct-4bit",
            ollamaId: "phi3.5:latest",
            params: "3.8B"
        ),
    ]

    /// Filter models by Ollama ID prefix match.
    public static func filter(ids: [String]) -> [ModelSpec] {
        all.filter { spec in
            ids.contains { id in
                spec.ollamaId.hasPrefix(id) || spec.name.lowercased().contains(id.lowercased())
            }
        }
    }
}
