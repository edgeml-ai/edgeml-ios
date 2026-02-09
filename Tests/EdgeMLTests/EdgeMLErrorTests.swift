import XCTest
@testable import EdgeML

final class EdgeMLErrorTests: XCTestCase {

    // MARK: - Error Description Tests

    func testNetworkErrors() {
        XCTAssertNotNil(EdgeMLError.networkUnavailable.errorDescription)
        XCTAssertTrue(EdgeMLError.networkUnavailable.errorDescription!.contains("Network"))

        XCTAssertNotNil(EdgeMLError.requestTimeout.errorDescription)
        XCTAssertTrue(EdgeMLError.requestTimeout.errorDescription!.contains("timed out"))
    }

    func testServerErrors() {
        let error = EdgeMLError.serverError(statusCode: 500, message: "Internal Server Error")
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("500"))
        XCTAssertTrue(error.errorDescription!.contains("Internal Server Error"))
    }

    func testAuthenticationErrors() {
        XCTAssertNotNil(EdgeMLError.invalidAPIKey.errorDescription)
        XCTAssertTrue(EdgeMLError.invalidAPIKey.errorDescription!.contains("API key"))

        XCTAssertNotNil(EdgeMLError.deviceNotRegistered.errorDescription)
        XCTAssertTrue(EdgeMLError.deviceNotRegistered.errorDescription!.contains("registered"))

        let authError = EdgeMLError.authenticationFailed(reason: "Token expired")
        XCTAssertTrue(authError.errorDescription!.contains("Token expired"))
    }

    func testModelErrors() {
        let notFoundError = EdgeMLError.modelNotFound(modelId: "test-model")
        XCTAssertTrue(notFoundError.errorDescription!.contains("test-model"))

        let versionError = EdgeMLError.versionNotFound(modelId: "test-model", version: "1.0.0")
        XCTAssertTrue(versionError.errorDescription!.contains("1.0.0"))
        XCTAssertTrue(versionError.errorDescription!.contains("test-model"))

        XCTAssertNotNil(EdgeMLError.checksumMismatch.errorDescription)
        XCTAssertTrue(EdgeMLError.checksumMismatch.errorDescription!.contains("checksum"))

        let compilationError = EdgeMLError.modelCompilationFailed(reason: "Invalid format")
        XCTAssertTrue(compilationError.errorDescription!.contains("Invalid format"))

        let formatError = EdgeMLError.unsupportedModelFormat(format: "custom")
        XCTAssertTrue(formatError.errorDescription!.contains("custom"))
    }

    func testTrainingErrors() {
        let trainingError = EdgeMLError.trainingFailed(reason: "Out of memory")
        XCTAssertTrue(trainingError.errorDescription!.contains("Out of memory"))

        XCTAssertNotNil(EdgeMLError.trainingNotSupported.errorDescription)
        XCTAssertTrue(EdgeMLError.trainingNotSupported.errorDescription!.contains("training"))

        let weightError = EdgeMLError.weightExtractionFailed(reason: "Invalid layer")
        XCTAssertTrue(weightError.errorDescription!.contains("Invalid layer"))

        let uploadError = EdgeMLError.uploadFailed(reason: "Network error")
        XCTAssertTrue(uploadError.errorDescription!.contains("Network error"))
    }

    func testCacheErrors() {
        let cacheError = EdgeMLError.cacheError(reason: "Disk full")
        XCTAssertTrue(cacheError.errorDescription!.contains("Disk full"))

        XCTAssertNotNil(EdgeMLError.insufficientStorage.errorDescription)
        XCTAssertTrue(EdgeMLError.insufficientStorage.errorDescription!.contains("storage"))
    }

    func testKeychainErrors() {
        let keychainError = EdgeMLError.keychainError(status: -25300)
        XCTAssertNotNil(keychainError.errorDescription)
        XCTAssertTrue(keychainError.errorDescription!.contains("-25300"))
    }

    func testGeneralErrors() {
        let unknownError = EdgeMLError.unknown(underlying: NSError(domain: "test", code: 1))
        XCTAssertNotNil(unknownError.errorDescription)

        let unknownNilError = EdgeMLError.unknown(underlying: nil)
        XCTAssertNotNil(unknownNilError.errorDescription)

        XCTAssertNotNil(EdgeMLError.cancelled.errorDescription)
        XCTAssertTrue(EdgeMLError.cancelled.errorDescription!.contains("cancelled"))
    }

    // MARK: - Recovery Suggestion Tests

    func testRecoverySuggestions() {
        XCTAssertNotNil(EdgeMLError.networkUnavailable.recoverySuggestion)
        XCTAssertNotNil(EdgeMLError.requestTimeout.recoverySuggestion)
        XCTAssertNotNil(EdgeMLError.invalidAPIKey.recoverySuggestion)
        XCTAssertNotNil(EdgeMLError.deviceNotRegistered.recoverySuggestion)
        XCTAssertNotNil(EdgeMLError.checksumMismatch.recoverySuggestion)
        XCTAssertNotNil(EdgeMLError.insufficientStorage.recoverySuggestion)
        XCTAssertNotNil(EdgeMLError.trainingNotSupported.recoverySuggestion)
    }
}
