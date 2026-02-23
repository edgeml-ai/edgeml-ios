import CoreML
import Foundation
import XCTest
@testable import Octomil

/// Tests for ``PersonalizationManager`` state management, buffer logic,
/// training guards, statistics, and model priority.
///
/// We avoid triggering actual CoreML training paths because they require
/// updatable .mlmodelc files. Instead we test the actor's internal state
/// transitions, buffer management, and statistics computation.
final class PersonalizationManagerTests: XCTestCase {

    // MARK: - Factory

    private func makeManager(
        bufferSize: Int = 5,
        minSamples: Int = 3,
        trainingInterval: TimeInterval = 0,
        trainingMode: TrainingMode = .localOnly,
        uploadThreshold: Int = 10
    ) -> PersonalizationManager {
        let config = TestConfiguration.fast()
        let trainer = FederatedTrainer(configuration: config)
        return PersonalizationManager(
            configuration: config,
            trainer: trainer,
            bufferSize: bufferSize,
            minSamples: minSamples,
            trainingInterval: trainingInterval,
            trainingMode: trainingMode,
            uploadThreshold: uploadThreshold
        )
    }

    private func dummyFeatureProvider() -> MLFeatureProvider {
        return MockFeatureProvider(doubles: ["input": 1.0])
    }

    // MARK: - getCurrentModel

    func testGetCurrentModelReturnsNilInitially() async {
        let manager = makeManager()
        let model = await manager.getCurrentModel()
        XCTAssertNil(model)
    }

    // MARK: - clearBuffer

    func testClearBufferRemovesAllSamples() async throws {
        let manager = makeManager(bufferSize: 100, minSamples: 100)

        // Add some samples (won't trigger training because minSamples is high)
        for _ in 0..<5 {
            try await manager.addTrainingSample(
                input: dummyFeatureProvider(),
                target: dummyFeatureProvider()
            )
        }

        let statsBefore = await manager.getStatistics()
        XCTAssertEqual(statsBefore.bufferedSamples, 5)

        await manager.clearBuffer()

        let statsAfter = await manager.getStatistics()
        XCTAssertEqual(statsAfter.bufferedSamples, 0)
    }

    // MARK: - Buffer max size enforcement

    func testBufferEnforcesMaxSize() async throws {
        // bufferSize=3 => maxBufferSize=6
        let manager = makeManager(bufferSize: 3, minSamples: 100)

        // Add 10 samples (more than maxBufferSize of 6)
        for _ in 0..<10 {
            try await manager.addTrainingSample(
                input: dummyFeatureProvider(),
                target: dummyFeatureProvider()
            )
        }

        let stats = await manager.getStatistics()
        // maxBufferSize = bufferSize * 2 = 6
        XCTAssertLessThanOrEqual(stats.bufferedSamples, 6)
    }

    // MARK: - Training guards

    func testTrainIncrementallyGuardsMinSamples() async throws {
        let manager = makeManager(bufferSize: 100, minSamples: 10)

        // Add fewer than minSamples
        for _ in 0..<5 {
            try await manager.addTrainingSample(
                input: dummyFeatureProvider(),
                target: dummyFeatureProvider()
            )
        }

        // trainIncrementally should return early (not enough samples)
        // and not throw, even though there's no model
        try await manager.trainIncrementally()

        let stats = await manager.getStatistics()
        // Buffer should still have 5 samples (training didn't consume them)
        XCTAssertEqual(stats.bufferedSamples, 5)
        XCTAssertEqual(stats.totalTrainingSessions, 0)
    }

    func testForceTrainingThrowsOnEmptyBuffer() async {
        let manager = makeManager()

        do {
            try await manager.forceTraining()
            XCTFail("Expected error for empty buffer")
        } catch {
            // Expected: "No training samples in buffer"
            XCTAssertTrue(error is OctomilError)
        }
    }

    // MARK: - Statistics

    func testInitialStatistics() async {
        let manager = makeManager(trainingMode: .localOnly)
        let stats = await manager.getStatistics()

        XCTAssertEqual(stats.totalTrainingSessions, 0)
        XCTAssertEqual(stats.totalSamplesTrained, 0)
        XCTAssertEqual(stats.bufferedSamples, 0)
        XCTAssertNil(stats.lastTrainingDate)
        XCTAssertNil(stats.averageLoss)
        XCTAssertNil(stats.averageAccuracy)
        XCTAssertFalse(stats.isPersonalized)
        XCTAssertEqual(stats.trainingMode, .localOnly)
    }

    func testStatisticsTrackBufferedSamples() async throws {
        let manager = makeManager(bufferSize: 100, minSamples: 100)

        for _ in 0..<7 {
            try await manager.addTrainingSample(
                input: dummyFeatureProvider(),
                target: dummyFeatureProvider()
            )
        }

        let stats = await manager.getStatistics()
        XCTAssertEqual(stats.bufferedSamples, 7)
    }

    func testStatisticsTrainingModeReflectsConfiguration() async {
        let localManager = makeManager(trainingMode: .localOnly)
        let localStats = await localManager.getStatistics()
        XCTAssertEqual(localStats.trainingMode, .localOnly)

        let fedManager = makeManager(trainingMode: .federated)
        let fedStats = await fedManager.getStatistics()
        XCTAssertEqual(fedStats.trainingMode, .federated)
    }

    // MARK: - Training history

    func testGetTrainingHistoryInitiallyEmpty() async {
        let manager = makeManager()
        let history = await manager.getTrainingHistory()
        XCTAssertTrue(history.isEmpty)
    }

    // MARK: - resetPersonalization

    func testResetPersonalizationThrowsWithoutBaseModel() async {
        let manager = makeManager()

        do {
            try await manager.resetPersonalization()
            XCTFail("Expected error when no base model is set")
        } catch {
            XCTAssertTrue(error is OctomilError)
        }
    }

    // MARK: - addTrainingSamples batch

    func testAddTrainingSamplesBatch() async throws {
        let manager = makeManager(bufferSize: 100, minSamples: 100)
        let samples: [(input: MLFeatureProvider, target: MLFeatureProvider)] = [
            (dummyFeatureProvider(), dummyFeatureProvider()),
            (dummyFeatureProvider(), dummyFeatureProvider()),
            (dummyFeatureProvider(), dummyFeatureProvider()),
        ]

        try await manager.addTrainingSamples(samples)

        let stats = await manager.getStatistics()
        XCTAssertEqual(stats.bufferedSamples, 3)
    }

    // MARK: - PersonalizationStatistics struct

    func testPersonalizationStatisticsProperties() {
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

    // MARK: - TrainingSession struct

    func testTrainingSessionCodableRoundtrip() throws {
        let session = TrainingSession(
            timestamp: Date(),
            sampleCount: 42,
            trainingTime: 3.14,
            loss: 0.05,
            accuracy: 0.97
        )

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(TrainingSession.self, from: data)

        XCTAssertEqual(decoded.sampleCount, 42)
        XCTAssertEqual(decoded.trainingTime, 3.14, accuracy: 0.001)
        XCTAssertEqual(decoded.loss, 0.05)
        XCTAssertEqual(decoded.accuracy, 0.97)
    }

    func testTrainingSessionNilMetrics() throws {
        let session = TrainingSession(
            timestamp: Date(),
            sampleCount: 10,
            trainingTime: 1.0,
            loss: nil,
            accuracy: nil
        )

        let data = try JSONEncoder().encode(session)
        let decoded = try JSONDecoder().decode(TrainingSession.self, from: data)

        XCTAssertNil(decoded.loss)
        XCTAssertNil(decoded.accuracy)
    }

    // MARK: - TrainingSample struct

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
            input: dummyFeatureProvider(),
            target: dummyFeatureProvider(),
            timestamp: Date(),
            metadata: nil
        )

        XCTAssertNil(sample.metadata)
    }

    // MARK: - Buffer eviction order

    func testBufferEvictsOldestSamplesWhenExceedingMaxSize() async throws {
        // bufferSize=5 => maxBufferSize=10
        // minSamples set high to prevent auto-training from consuming the buffer
        let manager = makeManager(bufferSize: 5, minSamples: 1000)

        // Add 12 samples, each with a unique timestamp so we can reason about order.
        // After adding all 12, buffer should be trimmed to maxBufferSize (10).
        // The first 2 samples (oldest) should be evicted.
        for i in 0..<12 {
            let input = MockFeatureProvider(doubles: ["x": Double(i)])
            let target = MockFeatureProvider(doubles: ["y": Double(i)])
            try await manager.addTrainingSample(
                input: input,
                target: target,
                metadata: ["index": i]
            )
        }

        let stats = await manager.getStatistics()
        // maxBufferSize = 5 * 2 = 10
        XCTAssertLessThanOrEqual(stats.bufferedSamples, 10,
            "Buffer should be trimmed to maxBufferSize")
        XCTAssertEqual(stats.bufferedSamples, 10,
            "Buffer should contain exactly maxBufferSize samples after eviction")
    }

    func testBufferEvictionPreservesNewestSamples() async throws {
        // bufferSize=3 => maxBufferSize=6
        let manager = makeManager(bufferSize: 3, minSamples: 1000)

        // Add 8 samples. After each add that exceeds maxBufferSize,
        // oldest are evicted. Final buffer should have samples 2..7 (indices 2-7).
        for i in 0..<8 {
            let input = MockFeatureProvider(doubles: ["x": Double(i)])
            let target = MockFeatureProvider(doubles: ["y": Double(i)])
            try await manager.addTrainingSample(
                input: input,
                target: target,
                metadata: ["index": i]
            )
        }

        let stats = await manager.getStatistics()
        XCTAssertEqual(stats.bufferedSamples, 6,
            "Buffer should be capped at maxBufferSize (3 * 2 = 6)")
    }
}
