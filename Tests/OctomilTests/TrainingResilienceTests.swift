import Foundation
import XCTest
@testable import Octomil

/// Tests for client-side training resilience: eligibility checks, gradient caching,
/// and network quality assessment.
final class TrainingResilienceTests: XCTestCase {

    // MARK: - TrainingEligibility: Battery Tests

    func testBatteryBelowThresholdSkipsTraining() {
        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.10,
            batteryState: .unplugged,
            thermalState: .nominal,
            availableMemoryMB: 1024,
            isLowPowerMode: false
        )
        let policy = OctomilConfiguration.TrainingPolicy(
            requireChargingForTraining: false,
            minimumBatteryLevel: 0.2
        )

        let result = TrainingEligibility.check(deviceState: state, policy: policy)

        XCTAssertFalse(result.eligible)
        XCTAssertEqual(result.reason, .lowBattery)
    }

    func testChargingWithLowBatteryAllowsTraining() {
        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.10,
            batteryState: .charging,
            thermalState: .nominal,
            availableMemoryMB: 1024,
            isLowPowerMode: false
        )
        let policy = OctomilConfiguration.TrainingPolicy(
            requireChargingForTraining: false,
            minimumBatteryLevel: 0.2
        )

        let result = TrainingEligibility.check(deviceState: state, policy: policy)

        XCTAssertTrue(result.eligible)
        XCTAssertNil(result.reason)
    }

    func testBatteryAboveThresholdAllowsTraining() {
        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.80,
            batteryState: .unplugged,
            thermalState: .nominal,
            availableMemoryMB: 1024,
            isLowPowerMode: false
        )
        let policy = OctomilConfiguration.TrainingPolicy(
            requireChargingForTraining: false,
            minimumBatteryLevel: 0.2
        )

        let result = TrainingEligibility.check(deviceState: state, policy: policy)

        XCTAssertTrue(result.eligible)
        XCTAssertNil(result.reason)
    }

    // MARK: - TrainingEligibility: Thermal Tests

    func testThermalStateCriticalSkipsTraining() {
        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.80,
            batteryState: .unplugged,
            thermalState: .critical,
            availableMemoryMB: 1024,
            isLowPowerMode: false
        )
        let policy = OctomilConfiguration.TrainingPolicy(
            requireChargingForTraining: false,
            minimumBatteryLevel: 0.2
        )

        let result = TrainingEligibility.check(deviceState: state, policy: policy)

        XCTAssertFalse(result.eligible)
        XCTAssertEqual(result.reason, .thermalPressure)
    }

    func testThermalStateSeriousSkipsTraining() {
        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.80,
            batteryState: .unplugged,
            thermalState: .serious,
            availableMemoryMB: 1024,
            isLowPowerMode: false
        )
        let policy = OctomilConfiguration.TrainingPolicy(
            requireChargingForTraining: false,
            minimumBatteryLevel: 0.2
        )

        let result = TrainingEligibility.check(deviceState: state, policy: policy)

        XCTAssertFalse(result.eligible)
        XCTAssertEqual(result.reason, .thermalPressure)
    }

    // MARK: - TrainingEligibility: Low Power Mode

    func testLowPowerModeSkipsTraining() {
        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.80,
            batteryState: .unplugged,
            thermalState: .nominal,
            availableMemoryMB: 1024,
            isLowPowerMode: true
        )
        let policy = OctomilConfiguration.TrainingPolicy(
            requireChargingForTraining: false,
            minimumBatteryLevel: 0.2
        )

        let result = TrainingEligibility.check(deviceState: state, policy: policy)

        XCTAssertFalse(result.eligible)
        XCTAssertEqual(result.reason, .lowPowerMode)
    }

    // MARK: - TrainingEligibility: Charging Required

    func testRequiresChargingWhenNotCharging() {
        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.80,
            batteryState: .unplugged,
            thermalState: .nominal,
            availableMemoryMB: 1024,
            isLowPowerMode: false
        )
        let policy = OctomilConfiguration.TrainingPolicy(
            requireChargingForTraining: true,
            minimumBatteryLevel: 0.2
        )

        let result = TrainingEligibility.check(deviceState: state, policy: policy)

        XCTAssertFalse(result.eligible)
        XCTAssertEqual(result.reason, .notCharging)
    }

    func testRequiresChargingWhenCharging() {
        let state = DeviceStateMonitor.DeviceState(
            batteryLevel: 0.80,
            batteryState: .charging,
            thermalState: .nominal,
            availableMemoryMB: 1024,
            isLowPowerMode: false
        )
        let policy = OctomilConfiguration.TrainingPolicy(
            requireChargingForTraining: true,
            minimumBatteryLevel: 0.2
        )

        let result = TrainingEligibility.check(deviceState: state, policy: policy)

        XCTAssertTrue(result.eligible)
        XCTAssertNil(result.reason)
    }

    // MARK: - GradientCache: Store and Retrieve

    func testGradientCacheStoresAndRetrieves() async {
        let cache = GradientCache(cacheDir: testCacheDir())
        let entry = GradientCacheEntry(
            roundId: "round-1",
            modelId: "model-A",
            modelVersion: "v1",
            weightsData: Data([0x01, 0x02, 0x03]),
            sampleCount: 100,
            createdAt: Date()
        )

        await cache.store(entry)
        let retrieved = await cache.retrieve(roundId: "round-1")

        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.roundId, "round-1")
        XCTAssertEqual(retrieved?.modelId, "model-A")
        XCTAssertEqual(retrieved?.weightsData, Data([0x01, 0x02, 0x03]))
        XCTAssertEqual(retrieved?.sampleCount, 100)
    }

    func testGradientCacheReturnsNilForMissing() async {
        let cache = GradientCache(cacheDir: testCacheDir())

        let result = await cache.retrieve(roundId: "nonexistent")

        XCTAssertNil(result)
    }

    func testGradientCacheListsPending() async {
        let cache = GradientCache(cacheDir: testCacheDir())

        let entry1 = GradientCacheEntry(
            roundId: "round-1",
            modelId: "model-A",
            modelVersion: "v1",
            weightsData: Data([0x01]),
            sampleCount: 50,
            createdAt: Date()
        )
        let entry2 = GradientCacheEntry(
            roundId: "round-2",
            modelId: "model-A",
            modelVersion: "v1",
            weightsData: Data([0x02]),
            sampleCount: 75,
            createdAt: Date()
        )

        await cache.store(entry1)
        await cache.store(entry2)
        let pending = await cache.pendingEntries()

        XCTAssertEqual(pending.count, 2)
    }

    func testGradientCacheRemoveEntry() async {
        let cache = GradientCache(cacheDir: testCacheDir())
        let entry = GradientCacheEntry(
            roundId: "round-1",
            modelId: "model-A",
            modelVersion: "v1",
            weightsData: Data([0x01]),
            sampleCount: 50,
            createdAt: Date()
        )

        await cache.store(entry)
        await cache.remove(roundId: "round-1")
        let result = await cache.retrieve(roundId: "round-1")

        XCTAssertNil(result)
    }

    func testGradientCacheMarkSubmitted() async {
        let cache = GradientCache(cacheDir: testCacheDir())
        let entry = GradientCacheEntry(
            roundId: "round-1",
            modelId: "model-A",
            modelVersion: "v1",
            weightsData: Data([0x01]),
            sampleCount: 50,
            createdAt: Date()
        )

        await cache.store(entry)
        let marked = await cache.markSubmitted(roundId: "round-1")
        XCTAssertTrue(marked)

        // Submitted entry should no longer appear in pending
        let pending = await cache.pendingEntries()
        XCTAssertEqual(pending.count, 0)

        // But should still be retrievable
        let retrieved = await cache.retrieve(roundId: "round-1")
        XCTAssertNotNil(retrieved)
        XCTAssertTrue(retrieved!.submitted)
    }

    func testGradientCachePurgeOld() async {
        let cache = GradientCache(cacheDir: testCacheDir())

        let oldDate = Date(timeIntervalSinceNow: -7200) // 2 hours ago
        let recentDate = Date(timeIntervalSinceNow: -60) // 1 minute ago

        let oldEntry = GradientCacheEntry(
            roundId: "old-round",
            modelId: "model-A",
            modelVersion: "v1",
            weightsData: Data([0x01]),
            sampleCount: 50,
            createdAt: oldDate
        )
        let recentEntry = GradientCacheEntry(
            roundId: "recent-round",
            modelId: "model-A",
            modelVersion: "v1",
            weightsData: Data([0x02]),
            sampleCount: 75,
            createdAt: recentDate
        )

        await cache.store(oldEntry)
        await cache.store(recentEntry)

        // Purge entries older than 1 hour
        let cutoff = Date(timeIntervalSinceNow: -3600)
        let purged = await cache.purgeOlderThan(cutoff)

        XCTAssertEqual(purged, 1)

        // Old entry should be gone
        let oldResult = await cache.retrieve(roundId: "old-round")
        XCTAssertNil(oldResult)

        // Recent entry should remain
        let recentResult = await cache.retrieve(roundId: "recent-round")
        XCTAssertNotNil(recentResult)
    }

    // MARK: - Network Suitability

    func testNetworkNotConnectedIsNotSuitable() {
        let quality = TrainingEligibility.assessNetworkQuality(
            isConnected: false,
            isExpensive: false,
            isConstrained: false
        )

        XCTAssertFalse(quality.suitable)
        XCTAssertEqual(quality.reason, .noConnection)
    }

    func testNetworkConnectedWiFiIsSuitable() {
        let quality = TrainingEligibility.assessNetworkQuality(
            isConnected: true,
            isExpensive: false,
            isConstrained: false
        )

        XCTAssertTrue(quality.suitable)
        XCTAssertNil(quality.reason)
    }

    func testNetworkExpensiveIsNotSuitable() {
        let quality = TrainingEligibility.assessNetworkQuality(
            isConnected: true,
            isExpensive: true,
            isConstrained: false
        )

        XCTAssertFalse(quality.suitable)
        XCTAssertEqual(quality.reason, .expensiveNetwork)
    }

    func testNetworkConstrainedIsNotSuitable() {
        let quality = TrainingEligibility.assessNetworkQuality(
            isConnected: true,
            isExpensive: false,
            isConstrained: true
        )

        XCTAssertFalse(quality.suitable)
        XCTAssertEqual(quality.reason, .constrainedNetwork)
    }

    // MARK: - Helpers

    private func testCacheDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("octomil-test-gradient-cache-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    override func tearDown() {
        super.tearDown()
        // Clean up temp dirs created during tests
        let tmpDir = FileManager.default.temporaryDirectory
        if let contents = try? FileManager.default.contentsOfDirectory(
            at: tmpDir,
            includingPropertiesForKeys: nil
        ) {
            for url in contents where url.lastPathComponent.hasPrefix("octomil-test-gradient-cache-") {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }
}
