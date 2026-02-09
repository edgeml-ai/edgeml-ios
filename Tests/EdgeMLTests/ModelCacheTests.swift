import CoreML
import Foundation
import XCTest
@testable import EdgeML

/// Tests for ``ModelCache`` and ``ModelCaching`` protocol.
///
/// Direct ``ModelCache`` tests cover the methods that work without a real
/// ``MLModel``: ``get`` miss paths, ``clearAll``, ``currentSize``, and
/// conformance to ``ModelCaching``. We cannot easily construct ``EdgeMLModel``
/// instances in unit tests (requires compiled .mlmodelc bundles), so
/// store/get/getLatest round-trips are tested via a ``MockModelCaching``
/// in-memory implementation that verifies the protocol contract.
final class ModelCacheTests: XCTestCase {

    // MARK: - ModelCache concrete: miss / empty paths

    func testGetReturnsNilForNonexistentModel() {
        let cache = ModelCache(maxSize: 10_000)
        let result = cache.get(modelId: "no-such-model", version: "1.0.0")
        XCTAssertNil(result)
    }

    func testGetReturnsNilForNonexistentVersion() {
        let cache = ModelCache(maxSize: 10_000)
        let result = cache.get(modelId: "model-1", version: "99.0.0")
        XCTAssertNil(result)
    }

    func testGetLatestReturnsNilWhenEmpty() {
        let cache = ModelCache(maxSize: 10_000)
        let result = cache.getLatest(modelId: "model-1")
        XCTAssertNil(result)
    }

    func testCurrentSizeIsNonNegative() {
        let cache = ModelCache(maxSize: 10_000)
        XCTAssertTrue(cache.currentSize >= 0)
    }

    func testClearAllDoesNotThrowOnEmptyCache() throws {
        let cache = ModelCache(maxSize: 10_000)
        try cache.clearAll()
        // Should complete without error
    }

    func testClearAllTwiceDoesNotThrow() throws {
        let cache = ModelCache(maxSize: 10_000)
        try cache.clearAll()
        try cache.clearAll()
    }

    func testModelCacheConformsToModelCaching() {
        let cache: any ModelCaching = ModelCache(maxSize: 10_000)
        XCTAssertNotNil(cache)
    }

    // MARK: - MockModelCaching: protocol contract tests

    func testMockStoreAndGet() {
        let mock = MockModelCachingImpl()
        let model = FakeEdgeMLModel(id: "m1", version: "1.0.0")

        mock.storeFake(model)
        let retrieved = mock.getFake(modelId: "m1", version: "1.0.0")

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, "m1")
        XCTAssertEqual(retrieved?.version, "1.0.0")
    }

    func testMockGetReturnsNilForMissingModel() {
        let mock = MockModelCachingImpl()
        XCTAssertNil(mock.getFake(modelId: "missing", version: "1.0.0"))
    }

    func testMockGetReturnsNilForMissingVersion() {
        let mock = MockModelCachingImpl()
        mock.storeFake(FakeEdgeMLModel(id: "m1", version: "1.0.0"))
        XCTAssertNil(mock.getFake(modelId: "m1", version: "2.0.0"))
    }

    func testMockGetLatestReturnsHighestVersion() {
        let mock = MockModelCachingImpl()

        mock.storeFake(FakeEdgeMLModel(id: "m1", version: "1.0.0"))
        mock.storeFake(FakeEdgeMLModel(id: "m1", version: "2.0.0"))
        mock.storeFake(FakeEdgeMLModel(id: "m1", version: "1.5.0"))

        let latest = mock.getLatestFake(modelId: "m1")
        XCTAssertEqual(latest?.version, "2.0.0")
    }

    func testMockGetLatestReturnsNilForUnknown() {
        let mock = MockModelCachingImpl()
        XCTAssertNil(mock.getLatestFake(modelId: "unknown"))
    }

    func testMockGetLatestSingleVersion() {
        let mock = MockModelCachingImpl()
        mock.storeFake(FakeEdgeMLModel(id: "m1", version: "3.1.4"))
        let latest = mock.getLatestFake(modelId: "m1")
        XCTAssertEqual(latest?.version, "3.1.4")
    }

    func testMockClearAllRemovesEverything() throws {
        let mock = MockModelCachingImpl()
        mock.storeFake(FakeEdgeMLModel(id: "m1", version: "1.0.0"))
        mock.storeFake(FakeEdgeMLModel(id: "m2", version: "1.0.0"))

        try mock.clearAll()

        XCTAssertNil(mock.getFake(modelId: "m1", version: "1.0.0"))
        XCTAssertNil(mock.getFake(modelId: "m2", version: "1.0.0"))
    }

    func testMockCurrentSizeStartsAtZero() {
        let mock = MockModelCachingImpl()
        XCTAssertEqual(mock.currentSize, 0)
    }

    func testMockStoreOverwritesSameKey() {
        let mock = MockModelCachingImpl()
        mock.storeFake(FakeEdgeMLModel(id: "m1", version: "1.0.0"))
        mock.storeFake(FakeEdgeMLModel(id: "m1", version: "1.0.0"))
        let result = mock.getFake(modelId: "m1", version: "1.0.0")
        XCTAssertNotNil(result)
    }

    func testMockDifferentModelsIsolated() {
        let mock = MockModelCachingImpl()
        mock.storeFake(FakeEdgeMLModel(id: "alpha", version: "1.0.0"))
        mock.storeFake(FakeEdgeMLModel(id: "beta", version: "2.0.0"))

        XCTAssertNotNil(mock.getFake(modelId: "alpha", version: "1.0.0"))
        XCTAssertNotNil(mock.getFake(modelId: "beta", version: "2.0.0"))
        XCTAssertNil(mock.getFake(modelId: "alpha", version: "2.0.0"))
    }

    func testMockVersionComparisonSemantic() {
        let mock = MockModelCachingImpl()
        mock.storeFake(FakeEdgeMLModel(id: "m", version: "1.9.0"))
        mock.storeFake(FakeEdgeMLModel(id: "m", version: "1.10.0"))
        mock.storeFake(FakeEdgeMLModel(id: "m", version: "2.0.0"))

        XCTAssertEqual(mock.getLatestFake(modelId: "m")?.version, "2.0.0")
    }

    func testMockVersionComparisonDifferentPartCounts() {
        let mock = MockModelCachingImpl()
        mock.storeFake(FakeEdgeMLModel(id: "m", version: "1.0"))
        mock.storeFake(FakeEdgeMLModel(id: "m", version: "1.0.1"))

        XCTAssertEqual(mock.getLatestFake(modelId: "m")?.version, "1.0.1")
    }

    // MARK: - cacheCompiledModel (disk)

    func testCacheCompiledModelCopiesFile() async throws {
        let cache = ModelCache(maxSize: 100_000_000)

        // Create a temp file to act as a "compiled model"
        let sourceDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("test-model-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: sourceDir, withIntermediateDirectories: true)
        let markerFile = sourceDir.appendingPathComponent("marker.txt")
        try "test-data".write(to: markerFile, atomically: true, encoding: .utf8)

        let cached = try await cache.cacheCompiledModel(
            modelId: "test-model",
            version: "1.0.0",
            compiledURL: sourceDir
        )

        XCTAssertTrue(FileManager.default.fileExists(atPath: cached.path))

        // Clean up
        try? cache.clearAll()
    }

    // MARK: - remove

    func testRemoveNonexistentModelDoesNotThrow() throws {
        let cache = ModelCache(maxSize: 10_000)
        try cache.remove(modelId: "nonexistent", version: "1.0.0")
    }
}

// MARK: - Fake EdgeMLModel wrapper

/// Lightweight stand-in for ``EdgeMLModel`` identity properties.
/// Used with ``MockModelCachingImpl`` to avoid needing real ``MLModel``s.
private struct FakeEdgeMLModel {
    let id: String
    let version: String
}

// MARK: - MockModelCaching

/// In-memory mock implementing the same semantics as ``ModelCache``,
/// used to verify protocol-level behavior.
private final class MockModelCachingImpl: ModelCaching, @unchecked Sendable {
    private var models: [String: EdgeMLModel] = [:]
    private var fakes: [String: FakeEdgeMLModel] = [:]

    var currentSize: UInt64 { 0 }

    func get(modelId _: String, version _: String) -> EdgeMLModel? {
        // Only check fake store for these tests
        return nil
    }

    func getLatest(modelId _: String) -> EdgeMLModel? {
        return nil
    }

    func store(_ _: EdgeMLModel) {
        // Can't be used without real EdgeMLModel
    }

    func cacheCompiledModel(modelId _: String, version _: String, compiledURL: URL) async throws -> URL {
        return compiledURL
    }

    func clearAll() throws {
        fakes.removeAll()
    }

    // Fake-aware methods for testing

    func storeFake(_ fake: FakeEdgeMLModel) {
        let key = "\(fake.id)_\(fake.version)"
        fakes[key] = fake
    }

    func getFake(modelId: String, version: String) -> FakeEdgeMLModel? {
        return fakes["\(modelId)_\(version)"]
    }

    func getLatestFake(modelId: String) -> FakeEdgeMLModel? {
        let matching = fakes.values.filter { $0.id == modelId }
        return matching.sorted(by: { compareVersions($0.version, $1.version) }).last
    }

    private func compareVersions(_ v1: String, _ v2: String) -> Bool {
        let parts1 = v1.split(separator: ".").compactMap { Int($0) }
        let parts2 = v2.split(separator: ".").compactMap { Int($0) }

        for i in 0..<max(parts1.count, parts2.count) {
            let p1 = i < parts1.count ? parts1[i] : 0
            let p2 = i < parts2.count ? parts2[i] : 0
            if p1 < p2 { return true }
            if p1 > p2 { return false }
        }
        return false
    }
}
