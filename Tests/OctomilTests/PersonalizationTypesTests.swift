import CoreML
import Foundation
import XCTest
@testable import Octomil

/// Tests for personalization supporting types:
/// ``TrainingMode``, ``TrainingSession``, ``PersonalizationStatistics``,
/// ``TrainingSample``, ``TrainingSampleBatchProvider``, and the
/// private ``Array.average()`` extension (tested indirectly).
final class PersonalizationTypesTests: XCTestCase {

    // MARK: - TrainingMode

    func testTrainingModeLocalOnlyRawValue() {
        XCTAssertEqual(TrainingMode.localOnly.rawValue, "local_only")
    }

    func testTrainingModeFederatedRawValue() {
        XCTAssertEqual(TrainingMode.federated.rawValue, "federated")
    }

    func testTrainingModeLocalOnlyDoesNotUpload() {
        XCTAssertFalse(TrainingMode.localOnly.uploadsToServer)
    }

    func testTrainingModeFederatedUploads() {
        XCTAssertTrue(TrainingMode.federated.uploadsToServer)
    }

    func testTrainingModeLocalOnlyDescription() {
        XCTAssertFalse(TrainingMode.localOnly.description.isEmpty)
        XCTAssertTrue(TrainingMode.localOnly.description.contains("never leaves"))
    }

    func testTrainingModeFederatedDescription() {
        XCTAssertFalse(TrainingMode.federated.description.isEmpty)
        XCTAssertTrue(TrainingMode.federated.description.contains("millions"))
    }

    func testTrainingModePrivacyLevel() {
        XCTAssertEqual(TrainingMode.localOnly.privacyLevel, "Maximum")
        XCTAssertEqual(TrainingMode.federated.privacyLevel, "High")
    }

    func testTrainingModeDataTransmitted() {
        XCTAssertEqual(TrainingMode.localOnly.dataTransmitted, "0 bytes")
        XCTAssertTrue(TrainingMode.federated.dataTransmitted.contains("Encrypted"))
    }

    func testTrainingModeCodableRoundTrip() throws {
        for mode in [TrainingMode.localOnly, .federated] {
            let data = try JSONEncoder().encode(mode)
            let decoded = try JSONDecoder().decode(TrainingMode.self, from: data)
            XCTAssertEqual(decoded, mode)
        }
    }

    func testTrainingModeDecodingFromRawString() throws {
        let json = "\"local_only\""
        let decoded = try JSONDecoder().decode(TrainingMode.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(decoded, .localOnly)
    }

    func testTrainingModeDecodingFederated() throws {
        let json = "\"federated\""
        let decoded = try JSONDecoder().decode(TrainingMode.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(decoded, .federated)
    }

    // MARK: - TrainingSession

    func testTrainingSessionProperties() {
        let now = Date()
        let session = TrainingSession(
            timestamp: now,
            sampleCount: 100,
            trainingTime: 5.5,
            loss: 0.02,
            accuracy: 0.98
        )

        XCTAssertEqual(session.timestamp, now)
        XCTAssertEqual(session.sampleCount, 100)
        XCTAssertEqual(session.trainingTime, 5.5, accuracy: 0.001)
        XCTAssertEqual(session.loss, 0.02)
        XCTAssertEqual(session.accuracy, 0.98)
    }

    func testTrainingSessionCodableRoundTrip() throws {
        let session = TrainingSession(
            timestamp: Date(timeIntervalSince1970: 1700000000),
            sampleCount: 42,
            trainingTime: 3.14,
            loss: 0.05,
            accuracy: 0.97
        )

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(session)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(TrainingSession.self, from: data)

        XCTAssertEqual(decoded.sampleCount, 42)
        XCTAssertEqual(decoded.trainingTime, 3.14, accuracy: 0.001)
        XCTAssertEqual(decoded.loss, 0.05)
        XCTAssertEqual(decoded.accuracy, 0.97)
    }

    func testTrainingSessionNilMetrics() throws {
        let session = TrainingSession(
            timestamp: Date(timeIntervalSince1970: 1700000000),
            sampleCount: 10,
            trainingTime: 1.0,
            loss: nil,
            accuracy: nil
        )

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(TrainingSession.self, from: data)

        XCTAssertNil(decoded.loss)
        XCTAssertNil(decoded.accuracy)
        XCTAssertEqual(decoded.sampleCount, 10)
    }

    // MARK: - PersonalizationStatistics

    func testPersonalizationStatisticsAllFields() {
        let now = Date()
        let stats = PersonalizationStatistics(
            totalTrainingSessions: 5,
            totalSamplesTrained: 250,
            bufferedSamples: 10,
            lastTrainingDate: now,
            averageLoss: 0.25,
            averageAccuracy: 0.92,
            isPersonalized: true,
            trainingMode: .federated
        )

        XCTAssertEqual(stats.totalTrainingSessions, 5)
        XCTAssertEqual(stats.totalSamplesTrained, 250)
        XCTAssertEqual(stats.bufferedSamples, 10)
        XCTAssertEqual(stats.lastTrainingDate, now)
        XCTAssertEqual(stats.averageLoss, 0.25)
        XCTAssertEqual(stats.averageAccuracy, 0.92)
        XCTAssertTrue(stats.isPersonalized)
        XCTAssertEqual(stats.trainingMode, .federated)
    }

    func testPersonalizationStatisticsNilOptionals() {
        let stats = PersonalizationStatistics(
            totalTrainingSessions: 0,
            totalSamplesTrained: 0,
            bufferedSamples: 0,
            lastTrainingDate: nil,
            averageLoss: nil,
            averageAccuracy: nil,
            isPersonalized: false,
            trainingMode: .localOnly
        )

        XCTAssertNil(stats.lastTrainingDate)
        XCTAssertNil(stats.averageLoss)
        XCTAssertNil(stats.averageAccuracy)
        XCTAssertFalse(stats.isPersonalized)
        XCTAssertEqual(stats.trainingMode, .localOnly)
    }

    // MARK: - TrainingSample

    func testTrainingSampleCreation() {
        let input = MockFeatureProvider(doubles: ["x": 1.0])
        let target = MockFeatureProvider(doubles: ["y": 0.0])
        let now = Date()

        let sample = TrainingSample(
            input: input,
            target: target,
            timestamp: now,
            metadata: ["source": "test"]
        )

        XCTAssertEqual(sample.timestamp, now)
        XCTAssertNotNil(sample.metadata)
        XCTAssertEqual(sample.metadata?["source"] as? String, "test")
    }

    func testTrainingSampleNilMetadata() {
        let sample = TrainingSample(
            input: MockFeatureProvider(doubles: ["x": 1.0]),
            target: MockFeatureProvider(doubles: ["y": 0.0]),
            timestamp: Date(),
            metadata: nil
        )

        XCTAssertNil(sample.metadata)
    }

    func testTrainingSampleInputAndTarget() {
        let input = MockFeatureProvider(doubles: ["a": 2.0, "b": 3.0])
        let target = MockFeatureProvider(doubles: ["label": 1.0])

        let sample = TrainingSample(
            input: input,
            target: target,
            timestamp: Date(),
            metadata: nil
        )

        XCTAssertTrue(sample.input.featureNames.contains("a"))
        XCTAssertTrue(sample.input.featureNames.contains("b"))
        XCTAssertTrue(sample.target.featureNames.contains("label"))
    }

    // MARK: - Average (tested indirectly via PersonalizationManager statistics)

    func testAverageViaStatistics() async {
        let config = TestConfiguration.fast()
        let trainer = FederatedTrainer(configuration: config)
        let manager = PersonalizationManager(
            configuration: config,
            trainer: trainer,
            bufferSize: 100,
            minSamples: 100,
            trainingMode: .localOnly
        )

        // With no training history, averages should be nil
        let stats = await manager.getStatistics()
        XCTAssertNil(stats.averageLoss)
        XCTAssertNil(stats.averageAccuracy)
    }
}
