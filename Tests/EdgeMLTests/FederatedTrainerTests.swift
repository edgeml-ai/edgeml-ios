import Foundation
import XCTest
@testable import EdgeML

/// Tests for ``FederatedTrainer`` and its supporting types
/// (``TrainingConfig``, ``TrainingResult``, ``WeightUpdate``).
///
/// CoreML `MLUpdateTask` requires a compiled updatable model on-device, so
/// we focus on the testable paths: initialization, config/result types, and
/// the weight update data model.
final class FederatedTrainerTests: XCTestCase {

    // MARK: - FederatedTrainer initialization

    func testInitCreatesTrainer() {
        let config = TestConfiguration.fast()
        let trainer = FederatedTrainer(configuration: config)
        XCTAssertNotNil(trainer)
    }

    func testInitWithLoggingEnabled() {
        let config = TestConfiguration.fast(enableLogging: true)
        let trainer = FederatedTrainer(configuration: config)
        XCTAssertNotNil(trainer)
    }

    // MARK: - TrainingConfig defaults

    func testTrainingConfigDefaults() {
        let config = TrainingConfig()
        XCTAssertEqual(config.epochs, 1)
        XCTAssertEqual(config.batchSize, 32)
        XCTAssertEqual(config.learningRate, 0.001, accuracy: 1e-9)
        XCTAssertTrue(config.shuffle)
    }

    func testTrainingConfigCustomValues() {
        let config = TrainingConfig(epochs: 5, batchSize: 64, learningRate: 0.01, shuffle: false)
        XCTAssertEqual(config.epochs, 5)
        XCTAssertEqual(config.batchSize, 64)
        XCTAssertEqual(config.learningRate, 0.01, accuracy: 1e-9)
        XCTAssertFalse(config.shuffle)
    }

    func testTrainingConfigStandard() {
        let standard = TrainingConfig.standard
        XCTAssertEqual(standard.epochs, 1)
        XCTAssertEqual(standard.batchSize, 32)
        XCTAssertEqual(standard.learningRate, 0.001, accuracy: 1e-9)
        XCTAssertTrue(standard.shuffle)
    }

    func testTrainingConfigCodableRoundtrip() throws {
        let original = TrainingConfig(epochs: 3, batchSize: 16, learningRate: 0.005, shuffle: false)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TrainingConfig.self, from: data)
        XCTAssertEqual(decoded.epochs, original.epochs)
        XCTAssertEqual(decoded.batchSize, original.batchSize)
        XCTAssertEqual(decoded.learningRate, original.learningRate, accuracy: 1e-9)
        XCTAssertEqual(decoded.shuffle, original.shuffle)
    }

    func testTrainingConfigPartialInit() {
        let config = TrainingConfig(epochs: 10)
        XCTAssertEqual(config.epochs, 10)
        // Other fields should be defaults
        XCTAssertEqual(config.batchSize, 32)
        XCTAssertEqual(config.learningRate, 0.001, accuracy: 1e-9)
        XCTAssertTrue(config.shuffle)
    }

    // MARK: - TrainingResult

    func testTrainingResultProperties() {
        let result = TrainingResult(
            sampleCount: 100,
            loss: 0.25,
            accuracy: 0.95,
            trainingTime: 5.5,
            metrics: ["epochs": 3.0, "batch_size": 32.0]
        )
        XCTAssertEqual(result.sampleCount, 100)
        XCTAssertEqual(result.loss, 0.25)
        XCTAssertEqual(result.accuracy, 0.95)
        XCTAssertEqual(result.trainingTime, 5.5, accuracy: 0.01)
        XCTAssertEqual(result.metrics.count, 2)
        XCTAssertEqual(result.metrics["epochs"], 3.0)
    }

    func testTrainingResultWithNilOptionals() {
        let result = TrainingResult(
            sampleCount: 50,
            loss: nil,
            accuracy: nil,
            trainingTime: 2.0,
            metrics: [:]
        )
        XCTAssertNil(result.loss)
        XCTAssertNil(result.accuracy)
        XCTAssertTrue(result.metrics.isEmpty)
    }

    func testTrainingResultCodableRoundtrip() throws {
        let original = TrainingResult(
            sampleCount: 200,
            loss: 0.1,
            accuracy: 0.98,
            trainingTime: 10.0,
            metrics: ["lr": 0.001]
        )
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(TrainingResult.self, from: data)
        XCTAssertEqual(decoded.sampleCount, original.sampleCount)
        XCTAssertEqual(decoded.loss, original.loss)
        XCTAssertEqual(decoded.accuracy, original.accuracy)
        XCTAssertEqual(decoded.trainingTime, original.trainingTime, accuracy: 0.01)
        XCTAssertEqual(decoded.metrics["lr"], original.metrics["lr"])
    }

    func testTrainingResultCodableWithNilLoss() throws {
        let original = TrainingResult(
            sampleCount: 10,
            loss: nil,
            accuracy: nil,
            trainingTime: 0.5,
            metrics: [:]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TrainingResult.self, from: data)
        XCTAssertNil(decoded.loss)
        XCTAssertNil(decoded.accuracy)
    }

    // MARK: - WeightUpdate

    func testWeightUpdateProperties() {
        let update = WeightUpdate(
            modelId: "model-1",
            version: "2.0",
            deviceId: "device-abc",
            weightsData: Data([0x01, 0x02, 0x03]),
            sampleCount: 500,
            metrics: ["loss": 0.15]
        )
        XCTAssertEqual(update.modelId, "model-1")
        XCTAssertEqual(update.version, "2.0")
        XCTAssertEqual(update.deviceId, "device-abc")
        XCTAssertEqual(update.weightsData.count, 3)
        XCTAssertEqual(update.sampleCount, 500)
        XCTAssertEqual(update.metrics["loss"], 0.15)
    }

    func testWeightUpdateNilDeviceId() {
        let update = WeightUpdate(
            modelId: "m",
            version: "1.0",
            deviceId: nil,
            weightsData: Data(),
            sampleCount: 0,
            metrics: [:]
        )
        XCTAssertNil(update.deviceId)
        XCTAssertTrue(update.weightsData.isEmpty)
    }

    func testWeightUpdateCodableRoundtrip() throws {
        let original = WeightUpdate(
            modelId: "model-2",
            version: "3.0",
            deviceId: nil,
            weightsData: Data([0xAA, 0xBB]),
            sampleCount: 100,
            metrics: ["accuracy": 0.9]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WeightUpdate.self, from: data)
        XCTAssertEqual(decoded.modelId, original.modelId)
        XCTAssertEqual(decoded.version, original.version)
        XCTAssertNil(decoded.deviceId)
        XCTAssertEqual(decoded.weightsData, original.weightsData)
        XCTAssertEqual(decoded.sampleCount, original.sampleCount)
    }

    func testWeightUpdateWithDeviceId() throws {
        let original = WeightUpdate(
            modelId: "m1",
            version: "1.0",
            deviceId: "device-123",
            weightsData: Data([0x00]),
            sampleCount: 50,
            metrics: [:]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(WeightUpdate.self, from: data)
        XCTAssertEqual(decoded.deviceId, "device-123")
    }

    func testWeightUpdateLargePayload() {
        let largeData = Data(repeating: 0xFF, count: 1024 * 1024) // 1MB
        let update = WeightUpdate(
            modelId: "big-model",
            version: "1.0",
            deviceId: nil,
            weightsData: largeData,
            sampleCount: 10000,
            metrics: ["loss": 0.01, "accuracy": 0.99]
        )
        XCTAssertEqual(update.weightsData.count, 1024 * 1024)
        XCTAssertEqual(update.metrics.count, 2)
    }

    // MARK: - RoundResult

    func testRoundResultCodableRoundtrip() throws {
        let trainingResult = TrainingResult(
            sampleCount: 50,
            loss: 0.3,
            accuracy: 0.85,
            trainingTime: 3.0,
            metrics: [:]
        )
        let original = RoundResult(
            roundId: "round-42",
            trainingResult: trainingResult,
            uploadSucceeded: true,
            completedAt: Date(timeIntervalSince1970: 1700000000)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let data = try encoder.encode(original)
        let decoded = try decoder.decode(RoundResult.self, from: data)
        XCTAssertEqual(decoded.roundId, "round-42")
        XCTAssertEqual(decoded.trainingResult.sampleCount, 50)
        XCTAssertTrue(decoded.uploadSucceeded)
    }

    func testRoundResultFailedUpload() {
        let result = RoundResult(
            roundId: "round-1",
            trainingResult: TrainingResult(
                sampleCount: 10,
                loss: 0.5,
                accuracy: nil,
                trainingTime: 1.0,
                metrics: [:]
            ),
            uploadSucceeded: false,
            completedAt: Date()
        )
        XCTAssertFalse(result.uploadSucceeded)
        XCTAssertEqual(result.roundId, "round-1")
    }
}
