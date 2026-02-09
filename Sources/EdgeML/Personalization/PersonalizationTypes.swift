import Foundation
import CoreML

// Supporting types for PersonalizationManager.

// MARK: - Training Sample

/// Represents a single training sample with metadata.
public struct TrainingSample {
    public let input: MLFeatureProvider
    public let target: MLFeatureProvider
    public let timestamp: Date
    public let metadata: [String: Any]?
}

/// Batch provider for training samples.
class TrainingSampleBatchProvider: NSObject, MLBatchProvider {
    let samples: [TrainingSample]

    init(samples: [TrainingSample]) {
        self.samples = samples
    }

    var count: Int {
        return samples.count
    }

    func features(at index: Int) -> MLFeatureProvider {
        return samples[index].input
    }
}

// MARK: - Training Session

/// Record of a training session.
public struct TrainingSession: Codable {
    public let timestamp: Date
    public let sampleCount: Int
    public let trainingTime: TimeInterval
    public let loss: Double?
    public let accuracy: Double?
}

// MARK: - Personalization Statistics

/// Statistics about personalization progress.
public struct PersonalizationStatistics {
    public let totalTrainingSessions: Int
    public let totalSamplesTrained: Int
    public let bufferedSamples: Int
    public let lastTrainingDate: Date?
    public let averageLoss: Double?
    public let averageAccuracy: Double?
    public let isPersonalized: Bool
    public let trainingMode: TrainingMode
    /// Whether a separate global model is maintained (Ditto mode).
    public let hasGlobalModel: Bool
    /// Number of personalized layers (FedPer mode).
    public let personalizedLayerCount: Int
}

// MARK: - Array Extension

extension Array where Element == Double {
    func average() -> Double? {
        guard !isEmpty else { return nil }
        return reduce(0, +) / Double(count)
    }
}
