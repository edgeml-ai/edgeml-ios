import XCTest
@testable import EdgeML

final class APIModelsTests: XCTestCase {

    // MARK: - Test Constants

    private static let testDownloadURL = "https://storage.example.com/models/fraud-v2.mlmodelc"

    // MARK: - Device Registration Tests

    func testDeviceCapabilitiesEncoding() throws {
        let capabilities = DeviceCapabilities(
            supportsTraining: true,
            coremlVersion: "5.0",
            hasNeuralEngine: true,
            maxBatchSize: 32,
            supportedFormats: ["coreml", "onnx"]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(capabilities)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["supports_training"] as? Bool, true)
        XCTAssertEqual(json["coreml_version"] as? String, "5.0")
        XCTAssertEqual(json["has_neural_engine"] as? Bool, true)
        XCTAssertEqual(json["max_batch_size"] as? Int, 32)
        XCTAssertEqual(json["supported_formats"] as? [String], ["coreml", "onnx"])
    }

    func testDeviceCapabilitiesDefaults() {
        let capabilities = DeviceCapabilities()

        XCTAssertTrue(capabilities.supportsTraining)
        XCTAssertNil(capabilities.coremlVersion)
        XCTAssertFalse(capabilities.hasNeuralEngine)
        XCTAssertNil(capabilities.maxBatchSize)
        XCTAssertNil(capabilities.supportedFormats)
    }

    func testDeviceRegistrationRequestEncoding() throws {
        let capabilities = DeviceCapabilities(
            supportsTraining: true,
            coremlVersion: "5.0",
            hasNeuralEngine: true
        )

        let request = DeviceRegistrationRequest(
            deviceIdentifier: "test-device-123",
            orgId: "test-org",
            platform: "ios",
            osVersion: nil,
            sdkVersion: nil,
            appVersion: nil,
            deviceInfo: nil,
            locale: nil,
            region: nil,
            timezone: nil,
            metadata: ["app_version": "1.0.0"],
            capabilities: capabilities
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["device_identifier"] as? String, "test-device-123")
        XCTAssertEqual(json["platform"] as? String, "ios")
        XCTAssertNotNil(json["capabilities"])
        XCTAssertNotNil(json["metadata"])
    }

    func testDeviceRegistrationResponseDecoding() throws {
        let json = """
        {
            "id": "abc-123",
            "device_identifier": "test-device",
            "org_id": "org-123",
            "status": "active",
            "registered_at": "2024-01-15T10:30:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let registration = try decoder.decode(DeviceRegistrationResponse.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(registration.id, "abc-123")
        XCTAssertEqual(registration.deviceIdentifier, "test-device")
        XCTAssertEqual(registration.orgId, "org-123")
        XCTAssertEqual(registration.status, "active")
        XCTAssertNotNil(registration.registeredAt)
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
        let config = TrainingConfig.standard

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

    // MARK: - Heartbeat Tests

    func testHeartbeatRequestEncodingWithMetadata() throws {
        let request = HeartbeatRequest(metadata: ["available_storage_mb": "2048"])

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        let metadata = json["metadata"] as? [String: String]
        XCTAssertEqual(metadata?["available_storage_mb"], "2048")
    }

    func testHeartbeatRequestEncodingWithoutMetadata() throws {
        let request = HeartbeatRequest()

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertTrue(json["metadata"] is NSNull || json["metadata"] == nil)
    }

    func testHeartbeatResponseDecoding() throws {
        let json = """
        {
            "id": "device-uuid-123",
            "device_identifier": "idfv-abc",
            "status": "active",
            "last_heartbeat": "2024-06-15T12:30:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let response = try decoder.decode(HeartbeatResponse.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(response.id, "device-uuid-123")
        XCTAssertEqual(response.deviceIdentifier, "idfv-abc")
        XCTAssertEqual(response.status, "active")
        XCTAssertNotNil(response.lastHeartbeat)
    }

    // MARK: - Model Update Info Tests

    func testModelUpdateInfoDecoding() throws {
        let json = """
        {
            "new_version": "2.1.0",
            "current_version": "2.0.0",
            "is_required": true,
            "release_notes": "Bug fixes and performance improvements",
            "update_size": 5242880
        }
        """

        let decoder = JSONDecoder()
        let info = try decoder.decode(ModelUpdateInfo.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(info.newVersion, "2.1.0")
        XCTAssertEqual(info.currentVersion, "2.0.0")
        XCTAssertTrue(info.isRequired)
        XCTAssertEqual(info.releaseNotes, "Bug fixes and performance improvements")
        XCTAssertEqual(info.updateSize, 5242880)
    }

    func testModelUpdateInfoDecodingWithNullReleaseNotes() throws {
        let json = """
        {
            "new_version": "1.1.0",
            "current_version": "1.0.0",
            "is_required": false,
            "release_notes": null,
            "update_size": 1024
        }
        """

        let decoder = JSONDecoder()
        let info = try decoder.decode(ModelUpdateInfo.self, from: json.data(using: .utf8)!)

        XCTAssertFalse(info.isRequired)
        XCTAssertNil(info.releaseNotes)
    }

    // MARK: - Download URL Response Tests

    func testDownloadURLResponseDecoding() throws {
        let json = """
        {
            "url": "\(Self.testDownloadURL)",
            "expires_at": "2024-06-15T13:00:00Z",
            "checksum": "sha256:abcdef1234567890",
            "file_size": 10485760
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let response = try decoder.decode(DownloadURLResponse.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(response.url, Self.testDownloadURL)
        XCTAssertEqual(response.checksum, "sha256:abcdef1234567890")
        XCTAssertEqual(response.fileSize, 10485760)
        XCTAssertNotNil(response.expiresAt)
    }

    // MARK: - Training Result Tests

    func testTrainingResultDecoding() throws {
        let json = """
        {
            "sample_count": 1000,
            "loss": 0.035,
            "accuracy": 0.97,
            "training_time": 12.5,
            "metrics": {"f1_score": 0.95, "precision": 0.96}
        }
        """

        let decoder = JSONDecoder()
        let result = try decoder.decode(TrainingResult.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(result.sampleCount, 1000)
        XCTAssertEqual(result.loss, 0.035)
        XCTAssertEqual(result.accuracy, 0.97)
        XCTAssertEqual(result.trainingTime, 12.5)
        XCTAssertEqual(result.metrics["f1_score"], 0.95)
        XCTAssertEqual(result.metrics["precision"], 0.96)
    }

    func testTrainingResultDecodingWithNullOptionals() throws {
        let json = """
        {
            "sample_count": 500,
            "loss": null,
            "accuracy": null,
            "training_time": 5.0,
            "metrics": {}
        }
        """

        let decoder = JSONDecoder()
        let result = try decoder.decode(TrainingResult.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(result.sampleCount, 500)
        XCTAssertNil(result.loss)
        XCTAssertNil(result.accuracy)
        XCTAssertEqual(result.trainingTime, 5.0)
        XCTAssertTrue(result.metrics.isEmpty)
    }

    // MARK: - Round Result Tests

    func testRoundResultDecoding() throws {
        let json = """
        {
            "round_id": "round-42",
            "training_result": {
                "sample_count": 200,
                "loss": 0.12,
                "accuracy": 0.88,
                "training_time": 8.0,
                "metrics": {}
            },
            "upload_succeeded": true,
            "completed_at": "2024-06-15T14:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let result = try decoder.decode(RoundResult.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(result.roundId, "round-42")
        XCTAssertEqual(result.trainingResult.sampleCount, 200)
        XCTAssertEqual(result.trainingResult.loss, 0.12)
        XCTAssertTrue(result.uploadSucceeded)
        XCTAssertNotNil(result.completedAt)
    }

    // MARK: - Weight Update Tests

    func testWeightUpdateEncoding() throws {
        let weightsData = Data([0x01, 0x02, 0x03, 0x04])
        let update = WeightUpdate(
            modelId: "fraud-detection",
            version: "2.0.0",
            deviceId: "device-uuid-123",
            weightsData: weightsData,
            sampleCount: 500,
            metrics: ["loss": 0.05, "accuracy": 0.98],
            roundId: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(update)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["model_id"] as? String, "fraud-detection")
        XCTAssertEqual(json["version"] as? String, "2.0.0")
        XCTAssertEqual(json["device_id"] as? String, "device-uuid-123")
        XCTAssertEqual(json["sample_count"] as? Int, 500)
        XCTAssertNotNil(json["weights_data"])
    }

    func testWeightUpdateRoundTrip() throws {
        let weightsData = Data(repeating: 0xAB, count: 64)
        let original = WeightUpdate(
            modelId: "model-abc",
            version: "1.0.0",
            deviceId: nil,
            weightsData: weightsData,
            sampleCount: 100,
            metrics: ["loss": 0.1],
            roundId: nil
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(WeightUpdate.self, from: data)

        XCTAssertEqual(decoded.modelId, original.modelId)
        XCTAssertEqual(decoded.version, original.version)
        XCTAssertNil(decoded.deviceId)
        XCTAssertEqual(decoded.weightsData, original.weightsData)
        XCTAssertEqual(decoded.sampleCount, original.sampleCount)
        XCTAssertEqual(decoded.metrics["loss"], original.metrics["loss"])
    }

    // MARK: - API Error Response Tests

    func testAPIErrorResponseDecoding() throws {
        let json = """
        {"detail": "Device not found"}
        """

        let decoder = JSONDecoder()
        let error = try decoder.decode(APIErrorResponse.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(error.detail, "Device not found")
    }

    // MARK: - Inference Event Metrics Tests

    func testInferenceEventMetricsEncoding() throws {
        let metrics = InferenceEventMetrics(
            ttfcMs: 45.2,
            chunkIndex: 3,
            chunkLatencyMs: 12.5,
            totalChunks: 10,
            totalDurationMs: 125.0,
            throughput: 80.0
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(metrics)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["ttfc_ms"] as? Double, 45.2)
        XCTAssertEqual(json["chunk_index"] as? Int, 3)
        XCTAssertEqual(json["chunk_latency_ms"] as? Double, 12.5)
        XCTAssertEqual(json["total_chunks"] as? Int, 10)
        XCTAssertEqual(json["total_duration_ms"] as? Double, 125.0)
        XCTAssertEqual(json["throughput"] as? Double, 80.0)
    }

    func testInferenceEventMetricsPartialFields() throws {
        let metrics = InferenceEventMetrics(ttfcMs: 30.0)

        let encoder = JSONEncoder()
        let data = try encoder.encode(metrics)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["ttfc_ms"] as? Double, 30.0)
        XCTAssertTrue(json["chunk_index"] is NSNull || json["chunk_index"] == nil)
    }

    func testInferenceEventMetricsRoundTrip() throws {
        let original = InferenceEventMetrics(
            ttfcMs: 50.0,
            chunkIndex: 5,
            chunkLatencyMs: 10.0,
            totalChunks: 20,
            totalDurationMs: 200.0,
            throughput: 100.0
        )

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(InferenceEventMetrics.self, from: data)

        XCTAssertEqual(decoded.ttfcMs, original.ttfcMs)
        XCTAssertEqual(decoded.chunkIndex, original.chunkIndex)
        XCTAssertEqual(decoded.chunkLatencyMs, original.chunkLatencyMs)
        XCTAssertEqual(decoded.totalChunks, original.totalChunks)
        XCTAssertEqual(decoded.totalDurationMs, original.totalDurationMs)
        XCTAssertEqual(decoded.throughput, original.throughput)
    }

    // MARK: - Inference Event Request Tests

    func testInferenceEventRequestEncoding() throws {
        let context = InferenceEventContext(
            deviceId: "device-123",
            modelId: "text-gen",
            version: "1.0.0",
            modality: "text",
            sessionId: "session-abc"
        )
        let request = InferenceEventRequest(
            context: context,
            eventType: "generation_started",
            timestampMs: 1718450000000,
            orgId: "org-42"
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["device_id"] as? String, "device-123")
        XCTAssertEqual(json["model_id"] as? String, "text-gen")
        XCTAssertEqual(json["version"] as? String, "1.0.0")
        XCTAssertEqual(json["modality"] as? String, "text")
        XCTAssertEqual(json["session_id"] as? String, "session-abc")
        XCTAssertEqual(json["event_type"] as? String, "generation_started")
        XCTAssertEqual(json["timestamp_ms"] as? Int64, 1718450000000)
        XCTAssertEqual(json["org_id"] as? String, "org-42")
    }

    func testInferenceEventRequestWithMetrics() throws {
        let metrics = InferenceEventMetrics(ttfcMs: 42.0, totalDurationMs: 500.0)
        let context = InferenceEventContext(
            deviceId: "d1",
            modelId: "m1",
            version: "1.0",
            modality: "text",
            sessionId: "s1"
        )
        let request = InferenceEventRequest(
            context: context,
            eventType: "generation_completed",
            timestampMs: 1000,
            metrics: metrics
        )

        let data = try JSONEncoder().encode(request)
        let decoded = try JSONDecoder().decode(InferenceEventRequest.self, from: data)

        XCTAssertEqual(decoded.metrics?.ttfcMs, 42.0)
        XCTAssertEqual(decoded.metrics?.totalDurationMs, 500.0)
        XCTAssertNil(decoded.orgId)
    }

    // MARK: - TrainingConfig Encoding Round-Trip

    func testTrainingConfigRoundTrip() throws {
        let original = TrainingConfig(epochs: 10, batchSize: 128, learningRate: 0.0001, shuffle: false)

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TrainingConfig.self, from: data)

        XCTAssertEqual(decoded.epochs, original.epochs)
        XCTAssertEqual(decoded.batchSize, original.batchSize)
        XCTAssertEqual(decoded.learningRate, original.learningRate)
        XCTAssertEqual(decoded.shuffle, original.shuffle)
    }

    // MARK: - Device Group Tests

    func testDeviceGroupDecoding() throws {
        let json = """
        {
            "id": "group-uuid-1",
            "name": "beta-testers",
            "description": "Beta testing group",
            "group_type": "static",
            "is_active": true,
            "device_count": 150,
            "tags": ["beta", "ios"],
            "created_at": "2024-01-01T00:00:00Z",
            "updated_at": "2024-06-15T12:00:00Z"
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let group = try decoder.decode(DeviceGroup.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(group.id, "group-uuid-1")
        XCTAssertEqual(group.name, "beta-testers")
        XCTAssertEqual(group.description, "Beta testing group")
        XCTAssertEqual(group.groupType, "static")
        XCTAssertTrue(group.isActive)
        XCTAssertEqual(group.deviceCount, 150)
        XCTAssertEqual(group.tags, ["beta", "ios"])
    }

    func testDeviceGroupsResponseDecoding() throws {
        let json = """
        {
            "groups": [
                {
                    "id": "g1",
                    "name": "group-a",
                    "description": null,
                    "group_type": "dynamic",
                    "is_active": true,
                    "device_count": 50,
                    "tags": null,
                    "created_at": "2024-01-01T00:00:00Z",
                    "updated_at": "2024-01-01T00:00:00Z"
                }
            ]
        }
        """

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let response = try decoder.decode(DeviceGroupsResponse.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(response.groups.count, 1)
        XCTAssertEqual(response.groups.first?.name, "group-a")
        XCTAssertNil(response.groups.first?.description)
        XCTAssertNil(response.groups.first?.tags)
    }

    // MARK: - AnyCodable Tests

    func testAnyCodableInt() throws {
        let json = """
        {"value": 42}
        """
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: json.data(using: .utf8)!)
        XCTAssertEqual(decoded["value"]?.value as? Int, 42)
    }

    func testAnyCodableString() throws {
        let json = """
        {"value": "hello"}
        """
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: json.data(using: .utf8)!)
        XCTAssertEqual(decoded["value"]?.value as? String, "hello")
    }

    func testAnyCodableDouble() throws {
        let json = """
        {"value": 3.14}
        """
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: json.data(using: .utf8)!)
        XCTAssertEqual(decoded["value"]?.value as? Double, 3.14)
    }

    func testAnyCodableBool() throws {
        let json = """
        {"value": true}
        """
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: json.data(using: .utf8)!)
        XCTAssertEqual(decoded["value"]?.value as? Bool, true)
    }

    func testAnyCodableNull() throws {
        let json = """
        {"value": null}
        """
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: json.data(using: .utf8)!)
        XCTAssertTrue(decoded["value"]?.value is NSNull)
    }

    func testAnyCodableRoundTrip() throws {
        let original: [String: AnyCodable] = [
            "int": AnyCodable(42),
            "string": AnyCodable("hello"),
            "double": AnyCodable(3.14),
            "bool": AnyCodable(true),
        ]

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode([String: AnyCodable].self, from: data)

        XCTAssertEqual(decoded["int"]?.value as? Int, 42)
        XCTAssertEqual(decoded["string"]?.value as? String, "hello")
        XCTAssertEqual(decoded["double"]?.value as? Double, 3.14)
        XCTAssertEqual(decoded["bool"]?.value as? Bool, true)
    }
}
