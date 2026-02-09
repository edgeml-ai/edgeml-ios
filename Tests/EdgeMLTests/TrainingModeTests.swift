import XCTest
@testable import EdgeML

final class TrainingModeTests: XCTestCase {

    // MARK: - Raw Value Tests

    func testLocalOnlyRawValue() {
        XCTAssertEqual(TrainingMode.localOnly.rawValue, "local_only")
    }

    func testFederatedRawValue() {
        XCTAssertEqual(TrainingMode.federated.rawValue, "federated")
    }

    // MARK: - Uploads To Server

    func testLocalOnlyDoesNotUpload() {
        XCTAssertFalse(TrainingMode.localOnly.uploadsToServer)
    }

    func testFederatedUploads() {
        XCTAssertTrue(TrainingMode.federated.uploadsToServer)
    }

    // MARK: - Privacy Level

    func testLocalOnlyHasMaximumPrivacy() {
        XCTAssertEqual(TrainingMode.localOnly.privacyLevel, "Maximum")
    }

    func testFederatedHasHighPrivacy() {
        XCTAssertEqual(TrainingMode.federated.privacyLevel, "High")
    }

    // MARK: - Description

    func testLocalOnlyDescription() {
        let desc = TrainingMode.localOnly.description
        XCTAssertTrue(desc.contains("never leaves"))
    }

    func testFederatedDescription() {
        let desc = TrainingMode.federated.description
        XCTAssertTrue(desc.contains("millions"))
        XCTAssertTrue(desc.contains("private"))
    }

    // MARK: - Data Transmitted

    func testLocalOnlyTransmitsNoData() {
        XCTAssertEqual(TrainingMode.localOnly.dataTransmitted, "0 bytes")
    }

    func testFederatedTransmitsOnlyDeltas() {
        let transmitted = TrainingMode.federated.dataTransmitted
        XCTAssertTrue(transmitted.contains("weight deltas"))
        XCTAssertTrue(transmitted.contains("Encrypted"))
    }

    // MARK: - Codable Round-Trip

    func testCodableRoundTripLocalOnly() throws {
        let original = TrainingMode.localOnly

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TrainingMode.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testCodableRoundTripFederated() throws {
        let original = TrainingMode.federated

        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(TrainingMode.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testDecodingFromRawString() throws {
        let json = "\"local_only\""
        let decoded = try JSONDecoder().decode(TrainingMode.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(decoded, .localOnly)
    }

    func testDecodingFederatedFromRawString() throws {
        let json = "\"federated\""
        let decoded = try JSONDecoder().decode(TrainingMode.self, from: json.data(using: .utf8)!)
        XCTAssertEqual(decoded, .federated)
    }

    func testDecodingInvalidRawValueThrows() {
        let json = "\"invalid_mode\""
        XCTAssertThrowsError(
            try JSONDecoder().decode(TrainingMode.self, from: json.data(using: .utf8)!)
        )
    }

    // MARK: - Privacy Semantics

    func testLocalOnlyIsMorePrivateThanFederated() {
        XCTAssertFalse(TrainingMode.localOnly.uploadsToServer)
        XCTAssertTrue(TrainingMode.federated.uploadsToServer)
        XCTAssertEqual(TrainingMode.localOnly.privacyLevel, "Maximum")
        XCTAssertEqual(TrainingMode.federated.privacyLevel, "High")
    }
}
