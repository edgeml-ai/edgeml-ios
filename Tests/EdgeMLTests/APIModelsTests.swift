import XCTest
@testable import EdgeML

final class APIModelsTests: XCTestCase {

    // MARK: - Device Registration Tests

    func testDeviceCapabilitiesEncoding() throws {
        let capabilities = DeviceCapabilities(
            supportsTraining: true,
            coreMLVersion: "5.0",
            osVersion: "17.0",
            deviceModel: "iPhone15,2",
            availableStorage: 1024 * 1024 * 1024,
            hasNeuralEngine: true
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(capabilities)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["supports_training"] as? Bool, true)
        XCTAssertEqual(json["coreml_version"] as? String, "5.0")
        XCTAssertEqual(json["os_version"] as? String, "17.0")
        XCTAssertEqual(json["device_model"] as? String, "iPhone15,2")
        XCTAssertEqual(json["available_storage"] as? UInt64, 1024 * 1024 * 1024)
        XCTAssertEqual(json["has_neural_engine"] as? Bool, true)
    }

    func testDeviceRegistrationRequestEncoding() throws {
        let capabilities = DeviceCapabilities(
            supportsTraining: true,
            coreMLVersion: "5.0",
            osVersion: "17.0",
            deviceModel: "iPhone15,2",
            availableStorage: 1024 * 1024 * 1024,
            hasNeuralEngine: true
        )

        let request = DeviceRegistrationRequest(
            deviceId: "test-device-123",
            metadata: ["app_version": "1.0.0"],
            capabilities: capabilities,
            platform: "ios"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["device_id"] as? String, "test-device-123")
        XCTAssertEqual(json["platform"] as? String, "ios")
        XCTAssertNotNil(json["capabilities"])
        XCTAssertNotNil(json["metadata"])
    }

    func testDeviceRegistrationDecoding() throws {
        let json = """
        {
            "device_id": "abc-123",
            "token": "secret-token",
            "registered_at": "2024-01-15T10:30:00Z",
            "bucket": 42
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let registration = try decoder.decode(DeviceRegistrationResponse.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(registration.deviceId, "abc-123")
        XCTAssertEqual(registration.token, "secret-token")
        XCTAssertEqual(registration.bucket, 42)
    }

    // MARK: - Model Metadata Tests

    func testModelMetadataDecoding() throws {
        let json = """
        {
            "model_id": "fraud-detection",
            "version": "1.2.0",
            "checksum": "abc123def456",
            "file_size": 10485760,
            "created_at": "2024-01-15T10:30:00Z",
            "format": "coreml",
            "supports_training": true,
            "description": "Fraud detection model",
            "input_schema": {"features": "float32"},
            "output_schema": {"prediction": "float32"}
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let metadata = try decoder.decode(ModelMetadata.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(metadata.modelId, "fraud-detection")
        XCTAssertEqual(metadata.version, "1.2.0")
        XCTAssertEqual(metadata.checksum, "abc123def456")
        XCTAssertEqual(metadata.fileSize, 10485760)
        XCTAssertEqual(metadata.format, "coreml")
        XCTAssertTrue(metadata.supportsTraining)
        XCTAssertEqual(metadata.description, "Fraud detection model")
    }

    // MARK: - Version Resolution Tests

    func testVersionResolutionDecoding() throws {
        let json = """
        {
            "version": "2.0.0",
            "source": "rollout",
            "experiment_id": null,
            "rollout_id": 5,
            "device_bucket": 23
        }
        """

        let decoder = JSONDecoder()
        let resolution = try decoder.decode(VersionResolutionResponse.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(resolution.version, "2.0.0")
        XCTAssertEqual(resolution.source, "rollout")
        XCTAssertNil(resolution.experimentId)
        XCTAssertEqual(resolution.rolloutId, 5)
        XCTAssertEqual(resolution.deviceBucket, 23)
    }

    // MARK: - Training Config Tests

    func testTrainingConfigDefaults() {
        let config = TrainingConfig.default

        XCTAssertEqual(config.epochs, 1)
        XCTAssertEqual(config.batchSize, 32)
        XCTAssertEqual(config.learningRate, 0.001)
        XCTAssertTrue(config.shuffle)
    }

    func testTrainingConfigCustom() {
        let config = TrainingConfig(
            epochs: 5,
            batchSize: 64,
            learningRate: 0.01,
            shuffle: false
        )

        XCTAssertEqual(config.epochs, 5)
        XCTAssertEqual(config.batchSize, 64)
        XCTAssertEqual(config.learningRate, 0.01)
        XCTAssertFalse(config.shuffle)
    }

    func testTrainingConfigEncoding() throws {
        let config = TrainingConfig(epochs: 3, batchSize: 16, learningRate: 0.005, shuffle: true)

        let encoder = JSONEncoder()
        let data = try encoder.encode(config)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["epochs"] as? Int, 3)
        XCTAssertEqual(json["batchSize"] as? Int, 16)
        XCTAssertEqual(json["learningRate"] as? Double, 0.005)
        XCTAssertEqual(json["shuffle"] as? Bool, true)
    }

    // MARK: - Tracking Event Tests

    func testTrackingEventCreation() {
        let now = Date()
        let event = TrackingEvent(
            name: "model_loaded",
            properties: ["model_id": "test", "version": "1.0.0"],
            timestamp: now
        )

        XCTAssertEqual(event.name, "model_loaded")
        XCTAssertEqual(event.properties["model_id"], "test")
        XCTAssertEqual(event.properties["version"], "1.0.0")
        XCTAssertEqual(event.timestamp, now)
    }

    func testTrackingEventDefaultTimestamp() {
        let beforeCreation = Date()
        let event = TrackingEvent(name: "test_event")
        let afterCreation = Date()

        XCTAssertGreaterThanOrEqual(event.timestamp, beforeCreation)
        XCTAssertLessThanOrEqual(event.timestamp, afterCreation)
        XCTAssertTrue(event.properties.isEmpty)
    }
}
