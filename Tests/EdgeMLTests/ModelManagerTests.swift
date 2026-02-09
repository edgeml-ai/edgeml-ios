import Foundation
import XCTest
@testable import EdgeML

/// Tests for ``ModelManager``.
///
/// Uses a ``MockModelCache`` (conforming to ``ModelCaching``) and
/// ``SharedMockURLProtocol`` to avoid real network and CoreML compilation.
///
/// Because ``EdgeMLModel`` requires a real ``MLModel`` (which needs a compiled
/// .mlmodel fixture), cache-hit tests verify the protocol delegation path
/// rather than constructing full model objects.
final class ModelManagerTests: XCTestCase {

    private var mockCache: MockModelCache!
    private var config: EdgeMLConfiguration!

    override func setUp() {
        super.setUp()
        config = TestConfiguration.fast()
        mockCache = MockModelCache()
        SharedMockURLProtocol.reset()
    }

    override func tearDown() {
        mockCache = nil
        config = nil
        SharedMockURLProtocol.reset()
        super.tearDown()
    }

    // MARK: - Cache access (nonisolated, synchronous)

    func testGetCachedModelReturnsNilWhenEmpty() {
        let manager = makeManager()
        XCTAssertNil(manager.getCachedModel(modelId: "nonexistent"))
    }

    func testGetCachedModelByVersionReturnsNilWhenEmpty() {
        let manager = makeManager()
        XCTAssertNil(manager.getCachedModel(modelId: "m1", version: "1.0"))
    }

    func testGetLatestDelegatesToCache() {
        mockCache.latestModelId = "m1"
        let manager = makeManager()
        // The mock returns nil (can't create real EdgeMLModel), but verifies delegation
        let _ = manager.getCachedModel(modelId: "m1")
        XCTAssertTrue(mockCache.getLatestCalled)
        XCTAssertEqual(mockCache.getLatestCalledWith, "m1")
    }

    func testGetByVersionDelegatesToCache() {
        let manager = makeManager()
        let _ = manager.getCachedModel(modelId: "m1", version: "2.0")
        XCTAssertTrue(mockCache.getCalled)
        XCTAssertEqual(mockCache.getCalledWithModelId, "m1")
        XCTAssertEqual(mockCache.getCalledWithVersion, "2.0")
    }

    // MARK: - Cache size

    func testGetCacheSizeReturnsZeroWhenEmpty() {
        let manager = makeManager()
        XCTAssertEqual(manager.getCacheSize(), 0)
    }

    func testGetCacheSizeReturnsMockValue() {
        mockCache.size = 1024 * 1024
        let manager = makeManager()
        XCTAssertEqual(manager.getCacheSize(), 1024 * 1024)
    }

    func testGetCacheSizeReflectsUpdates() {
        let manager = makeManager()
        XCTAssertEqual(manager.getCacheSize(), 0)
        mockCache.size = 500
        XCTAssertEqual(manager.getCacheSize(), 500)
        mockCache.size = 2000
        XCTAssertEqual(manager.getCacheSize(), 2000)
    }

    // MARK: - Clear cache

    func testClearCacheDelegatesToMock() async throws {
        let manager = makeManager()
        try await manager.clearCache()
        XCTAssertTrue(mockCache.clearAllCalled)
    }

    func testClearCacheThrowsWhenCacheThrows() async {
        mockCache.clearShouldThrow = true
        let manager = makeManager()
        do {
            try await manager.clearCache()
            XCTFail("Expected clearCache to throw")
        } catch {
            // Verify the error propagates
            if case EdgeMLError.cacheError = error {
                // Expected
            } else {
                XCTFail("Expected cacheError, got: \(error)")
            }
        }
    }

    func testClearCacheResetsState() async throws {
        mockCache.size = 5000
        let manager = makeManager()
        try await manager.clearCache()
        // After clearing, the mock resets its size
        XCTAssertEqual(mockCache.size, 0)
    }

    // MARK: - cacheCompiledModel delegation

    func testCacheCompiledModelDelegatesToMock() async throws {
        let tempDir = FileManager.default.temporaryDirectory
        let sourceURL = tempDir.appendingPathComponent("test_\(UUID().uuidString).mlmodelc")
        try Data("test".utf8).write(to: sourceURL)
        defer { try? FileManager.default.removeItem(at: sourceURL) }

        let resultURL = try await mockCache.cacheCompiledModel(
            modelId: "m1",
            version: "1.0",
            compiledURL: sourceURL
        )
        XCTAssertEqual(resultURL, sourceURL)
        XCTAssertTrue(mockCache.cacheCompiledCalled)
    }

    // MARK: - Download (network error paths)

    func testDownloadModelFailsWithNetworkError() async {
        SharedMockURLProtocol.responses = [
            .failure(URLError(.notConnectedToInternet))
        ]
        let manager = makeManager()
        do {
            let _ = try await manager.downloadModel(modelId: "m1", version: "1.0")
            XCTFail("Expected download to fail")
        } catch {
            // Network error should propagate
            XCTAssertNotNil(error)
        }
    }

    func testDownloadModelFailsWithServerError() async {
        // First request is getModelMetadata — return a server error
        SharedMockURLProtocol.responses = [
            .success(statusCode: 500, json: ["error": "Internal Server Error"])
        ]
        let manager = makeManager()
        do {
            let _ = try await manager.downloadModel(modelId: "m1", version: "1.0")
            XCTFail("Expected download to fail with server error")
        } catch {
            XCTAssertNotNil(error)
        }
    }

    // MARK: - ModelCaching protocol

    func testMockCacheConformsToModelCaching() {
        let _: any ModelCaching = mockCache
        // Compiles = conforms
    }

    // MARK: - Helpers

    private func makeManager() -> ModelManager {
        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.protocolClasses = [SharedMockURLProtocol.self]
        let apiClient = APIClient(
            serverURL: URL(string: "https://test.edgeml.ai")!,
            configuration: config,
            sessionConfiguration: sessionConfig
        )
        return ModelManager(
            apiClient: apiClient,
            configuration: config,
            modelCache: mockCache
        )
    }
}

// MARK: - MockModelCache

/// In-memory mock of ``ModelCaching`` for unit tests.
/// Returns nil for model lookups (can't construct real EdgeMLModel without .mlmodel)
/// but tracks all method calls for verification.
private final class MockModelCache: ModelCaching, @unchecked Sendable {
    var size: UInt64 = 0
    var clearAllCalled = false
    var clearShouldThrow = false
    var cacheCompiledCalled = false

    // get() tracking
    var getCalled = false
    var getCalledWithModelId: String?
    var getCalledWithVersion: String?

    // getLatest() tracking
    var getLatestCalled = false
    var getLatestCalledWith: String?
    var latestModelId: String?

    // store() tracking
    var storeCallCount = 0

    var currentSize: UInt64 { size }

    func get(modelId: String, version: String) -> EdgeMLModel? {
        getCalled = true
        getCalledWithModelId = modelId
        getCalledWithVersion = version
        return nil
    }

    func getLatest(modelId: String) -> EdgeMLModel? {
        getLatestCalled = true
        getLatestCalledWith = modelId
        return nil
    }

    func store(_ model: EdgeMLModel) {
        storeCallCount += 1
    }

    func cacheCompiledModel(modelId _: String, version _: String, compiledURL: URL) async throws -> URL {
        cacheCompiledCalled = true
        return compiledURL
    }

    func clearAll() throws {
        if clearShouldThrow {
            throw EdgeMLError.cacheError(reason: "Mock clear error")
        }
        clearAllCalled = true
        size = 0
    }
}
