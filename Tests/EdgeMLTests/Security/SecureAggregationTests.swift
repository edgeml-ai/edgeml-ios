import XCTest
@testable import EdgeML

final class SecureAggregationTests: XCTestCase {

    // MARK: - Shamir Secret Sharing

    func testShamirShareAndReconstruct() async throws {
        let client = SecureAggregationClient()

        let secret: [UInt64] = [42, 1337, 999999]
        let threshold = 3
        let totalShares = 5

        let shares = await client.generateShamirShares(
            secret: secret,
            threshold: threshold,
            totalShares: totalShares
        )

        XCTAssertEqual(shares.count, totalShares)
        for participantShares in shares {
            XCTAssertEqual(participantShares.count, secret.count)
        }

        // Reconstruct using exactly threshold shares
        let reconstructed = await client.reconstructFromShares(
            Array(shares.prefix(threshold)),
            threshold: threshold
        )

        XCTAssertEqual(reconstructed.count, secret.count)
        for (original, recovered) in zip(secret, reconstructed) {
            XCTAssertEqual(original, recovered, "Reconstructed value should match original")
        }
    }

    func testShamirReconstructWithDifferentSubsets() async throws {
        let client = SecureAggregationClient()

        let secret: [UInt64] = [12345]
        let threshold = 2
        let totalShares = 4

        let shares = await client.generateShamirShares(
            secret: secret,
            threshold: threshold,
            totalShares: totalShares
        )

        // Try different subsets of threshold shares
        let subset1 = [shares[0], shares[1]]
        let subset2 = [shares[1], shares[3]]
        let subset3 = [shares[0], shares[3]]

        let r1 = await client.reconstructFromShares(subset1, threshold: threshold)
        let r2 = await client.reconstructFromShares(subset2, threshold: threshold)
        let r3 = await client.reconstructFromShares(subset3, threshold: threshold)

        XCTAssertEqual(r1.first, secret.first)
        XCTAssertEqual(r2.first, secret.first)
        XCTAssertEqual(r3.first, secret.first)
    }

    func testShamirInsufficientSharesFails() async throws {
        let client = SecureAggregationClient()

        let secret: [UInt64] = [42]
        let threshold = 3
        let totalShares = 5

        let shares = await client.generateShamirShares(
            secret: secret,
            threshold: threshold,
            totalShares: totalShares
        )

        // Only provide threshold - 1 shares
        let insufficient = Array(shares.prefix(threshold - 1))
        let reconstructed = await client.reconstructFromShares(insufficient, threshold: threshold)

        // With insufficient shares the result should be empty
        XCTAssertTrue(reconstructed.isEmpty)
    }

    func testShamirSingleSecretSingleThreshold() async throws {
        let client = SecureAggregationClient()

        // threshold = 1 means any single share reconstructs the secret
        let secret: [UInt64] = [77]
        let shares = await client.generateShamirShares(
            secret: secret,
            threshold: 1,
            totalShares: 3
        )

        for i in 0..<shares.count {
            let result = await client.reconstructFromShares([shares[i]], threshold: 1)
            XCTAssertEqual(result.first, secret.first)
        }
    }

    // MARK: - Protocol Phases

    func testProtocolPhaseProgression() async throws {
        let client = SecureAggregationClient()

        let phase0 = await client.currentPhase
        XCTAssertEqual(phase0, .idle)

        let config = SecAggConfiguration(threshold: 2, totalClients: 3)
        await client.beginSession(sessionId: "test-session", clientIndex: 1, configuration: config)

        let phase1 = await client.currentPhase
        XCTAssertEqual(phase1, .shareKeys)

        _ = try await client.generateKeyShares()
        let phase2 = await client.currentPhase
        XCTAssertEqual(phase2, .maskedInput)

        let dummyWeights = Data(repeating: 0xAB, count: 64)
        _ = try await client.maskModelUpdate(dummyWeights)
        let phase3 = await client.currentPhase
        XCTAssertEqual(phase3, .unmasking)

        _ = try await client.provideUnmaskingShares(droppedClientIndices: [])
        let phase4 = await client.currentPhase
        XCTAssertEqual(phase4, .completed)

        await client.reset()
        let phase5 = await client.currentPhase
        XCTAssertEqual(phase5, .idle)
    }

    func testWrongPhaseThrows() async {
        let client = SecureAggregationClient()

        // Try to generate shares without starting a session
        do {
            _ = try await client.generateKeyShares()
            XCTFail("Should have thrown")
        } catch {
            // expected
        }

        // Try to mask without being in maskedInput phase
        do {
            _ = try await client.maskModelUpdate(Data([1, 2, 3]))
            XCTFail("Should have thrown")
        } catch {
            // expected
        }
    }

    // MARK: - Masking

    func testMaskingProducesDifferentOutput() async throws {
        let client = SecureAggregationClient()

        let config = SecAggConfiguration(threshold: 2, totalClients: 3)
        await client.beginSession(sessionId: "mask-test", clientIndex: 1, configuration: config)
        _ = try await client.generateKeyShares()

        let originalWeights = Data(repeating: 0x42, count: 128)
        let masked = try await client.maskModelUpdate(originalWeights)

        XCTAssertEqual(masked.count, originalWeights.count)
        XCTAssertNotEqual(masked, originalWeights, "Masked data should differ from original")
    }

    // MARK: - Serialization

    func testFieldElementSerialization() async throws {
        let client = SecureAggregationClient()

        let original = Data([0x00, 0x00, 0x00, 0x2A, 0x00, 0x00, 0x05, 0x39])
        let elements = await client.serializeToFieldElements(original)
        XCTAssertEqual(elements.count, 2)
        XCTAssertEqual(elements[0], 42) // 0x2A
        XCTAssertEqual(elements[1], 1337) // 0x539

        let roundTripped = await client.deserializeFromFieldElements(elements)
        XCTAssertEqual(roundTripped, original)
    }

    func testShareBundleSerialization() async throws {
        let client = SecureAggregationClient()

        let config = SecAggConfiguration(threshold: 2, totalClients: 3)
        await client.beginSession(sessionId: "serde-test", clientIndex: 1, configuration: config)

        let sharesData = try await client.generateKeyShares()
        XCTAssertTrue(sharesData.count > 0)

        // Deserialize and verify structure
        let bundles = await client.deserializeShareBundles(sharesData)
        XCTAssertEqual(bundles.count, 3)

        for bundle in bundles {
            XCTAssertTrue(bundle.count > 0)
            for share in bundle {
                XCTAssertTrue(share.index >= 1 && share.index <= 3)
                XCTAssertTrue(share.value.count > 0)
            }
        }
    }

    // MARK: - Configuration

    func testSecAggConfigurationDefaults() {
        let config = SecAggConfiguration(threshold: 3, totalClients: 5)

        XCTAssertEqual(config.threshold, 3)
        XCTAssertEqual(config.totalClients, 5)
        XCTAssertEqual(config.privacyBudget, 1.0)
        XCTAssertEqual(config.keyLength, 256)
    }

    // MARK: - API Model Encoding

    func testSecAggSessionResponseDecoding() throws {
        let json = """
        {
            "session_id": "sess-123",
            "round_id": "round-456",
            "client_index": 2,
            "threshold": 3,
            "total_clients": 5,
            "privacy_budget": 1.0,
            "key_length": 256
        }
        """

        let decoder = JSONDecoder()
        let response = try decoder.decode(SecAggSessionResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.sessionId, "sess-123")
        XCTAssertEqual(response.roundId, "round-456")
        XCTAssertEqual(response.clientIndex, 2)
        XCTAssertEqual(response.threshold, 3)
        XCTAssertEqual(response.totalClients, 5)
        XCTAssertEqual(response.privacyBudget, 1.0)
        XCTAssertEqual(response.keyLength, 256)
    }

    func testSecAggShareKeysRequestEncoding() throws {
        let request = SecAggShareKeysRequest(
            sessionId: "sess-123",
            deviceId: "dev-456",
            sharesData: "base64data=="
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(dict["session_id"] as? String, "sess-123")
        XCTAssertEqual(dict["device_id"] as? String, "dev-456")
        XCTAssertEqual(dict["shares_data"] as? String, "base64data==")
    }

    func testSecAggMaskedInputRequestEncoding() throws {
        let request = SecAggMaskedInputRequest(
            sessionId: "sess-123",
            deviceId: "dev-456",
            maskedWeightsData: "maskedbase64==",
            sampleCount: 100,
            metrics: ["loss": 0.5, "accuracy": 0.95]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(request)
        let dict = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(dict["session_id"] as? String, "sess-123")
        XCTAssertEqual(dict["sample_count"] as? Int, 100)
        XCTAssertEqual(dict["masked_weights_data"] as? String, "maskedbase64==")
    }

    func testSecAggUnmaskResponseDecoding() throws {
        let json = """
        {
            "dropped_client_indices": [2, 4],
            "unmasking_required": true
        }
        """

        let decoder = JSONDecoder()
        let response = try decoder.decode(SecAggUnmaskResponse.self, from: Data(json.utf8))

        XCTAssertEqual(response.droppedClientIndices, [2, 4])
        XCTAssertTrue(response.unmaskingRequired)
    }

    // MARK: - Edge Cases

    func testLargeSecretValues() async throws {
        let client = SecureAggregationClient()

        // Use values near the field boundary (2^61 - 1)
        let p: UInt64 = (1 << 61) - 1
        let secret: [UInt64] = [p - 1, p - 2, 0, 1]
        let threshold = 2
        let totalShares = 3

        let shares = await client.generateShamirShares(
            secret: secret,
            threshold: threshold,
            totalShares: totalShares
        )

        let reconstructed = await client.reconstructFromShares(
            Array(shares.prefix(threshold)),
            threshold: threshold
        )

        XCTAssertEqual(reconstructed.count, secret.count)
        for (original, recovered) in zip(secret, reconstructed) {
            XCTAssertEqual(original, recovered)
        }
    }

    func testZeroSecret() async throws {
        let client = SecureAggregationClient()

        let secret: [UInt64] = [0, 0, 0]
        let shares = await client.generateShamirShares(
            secret: secret,
            threshold: 2,
            totalShares: 3
        )

        let reconstructed = await client.reconstructFromShares(
            Array(shares.prefix(2)),
            threshold: 2
        )

        XCTAssertEqual(reconstructed, secret)
    }

    func testEmptyWeightsMasking() async throws {
        let client = SecureAggregationClient()

        let config = SecAggConfiguration(threshold: 2, totalClients: 3)
        await client.beginSession(sessionId: "empty-test", clientIndex: 1, configuration: config)
        _ = try await client.generateKeyShares()

        let emptyWeights = Data()
        let masked = try await client.maskModelUpdate(emptyWeights)
        XCTAssertEqual(masked.count, 0)
    }
}
