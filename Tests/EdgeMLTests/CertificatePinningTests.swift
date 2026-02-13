import XCTest
@testable import EdgeML

final class CertificatePinningTests: XCTestCase {

    // MARK: - SHA-256 Hashing

    func testSHA256ProducesCorrectLength() {
        let data = Data("hello world".utf8)
        let hash = CertificatePinningDelegate.sha256(data: data)
        XCTAssertEqual(hash.count, 32, "SHA-256 hash should be 32 bytes")
    }

    func testSHA256IsDeterministic() {
        let data = Data("test input".utf8)
        let hash1 = CertificatePinningDelegate.sha256(data: data)
        let hash2 = CertificatePinningDelegate.sha256(data: data)
        XCTAssertEqual(hash1, hash2, "SHA-256 should produce the same hash for the same input")
    }

    func testSHA256DifferentInputsDifferentHashes() {
        let data1 = Data("input one".utf8)
        let data2 = Data("input two".utf8)
        let hash1 = CertificatePinningDelegate.sha256(data: data1)
        let hash2 = CertificatePinningDelegate.sha256(data: data2)
        XCTAssertNotEqual(hash1, hash2, "Different inputs should produce different hashes")
    }

    // MARK: - Delegate Configuration

    func testDelegateCreatedWithPins() {
        let pins = ["dGVzdHBpbjE=", "dGVzdHBpbjI="]
        let delegate = CertificatePinningDelegate(pinnedHashes: pins)
        XCTAssertNotNil(delegate, "Delegate should be created with pin hashes")
    }

    func testDelegateCreatedWithoutPins() {
        let delegate = CertificatePinningDelegate(pinnedHashes: [])
        XCTAssertNotNil(delegate, "Delegate should be created with empty pin hashes for passthrough")
    }

    // MARK: - Configuration Integration

    func testConfigurationWithPins() {
        let config = EdgeMLConfiguration(
            pinnedCertificateHashes: ["abc123", "def456"]
        )
        XCTAssertEqual(config.pinnedCertificateHashes.count, 2)
    }

    func testConfigurationDefaultNoPins() {
        let config = EdgeMLConfiguration()
        XCTAssertTrue(config.pinnedCertificateHashes.isEmpty,
                       "Default configuration should have no pinned certificates")
    }

    func testStandardPresetHasNoPins() {
        let config = EdgeMLConfiguration.standard
        XCTAssertTrue(config.pinnedCertificateHashes.isEmpty)
    }

    func testDevelopmentPresetHasNoPins() {
        let config = EdgeMLConfiguration.development
        XCTAssertTrue(config.pinnedCertificateHashes.isEmpty)
    }

    func testProductionPresetHasNoPins() {
        let config = EdgeMLConfiguration.production
        XCTAssertTrue(config.pinnedCertificateHashes.isEmpty)
    }
}
