import CoreML
import Foundation

/// Minimal ``MLFeatureProvider`` for tests that don't need a real CoreML model.
final class MockFeatureProvider: NSObject, MLFeatureProvider {

    private let features: [String: MLFeatureValue]

    /// Feature names exposed by this provider.
    var featureNames: Set<String> {
        Set(features.keys)
    }

    /// Creates a provider backed by the supplied feature dictionary.
    init(features: [String: MLFeatureValue]) {
        self.features = features
        super.init()
    }

    /// Convenience: create from a `[String: Double]` dictionary.
    convenience init(doubles: [String: Double]) {
        var feats: [String: MLFeatureValue] = [:]
        for (k, v) in doubles {
            feats[k] = MLFeatureValue(double: v)
        }
        self.init(features: feats)
    }

    /// Convenience: create from a `[String: String]` dictionary.
    convenience init(strings: [String: String]) {
        var feats: [String: MLFeatureValue] = [:]
        for (k, v) in strings {
            feats[k] = MLFeatureValue(string: v)
        }
        self.init(features: feats)
    }

    func featureValue(for featureName: String) -> MLFeatureValue? {
        features[featureName]
    }
}
