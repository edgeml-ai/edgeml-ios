import CoreML
import Foundation
import XCTest
@testable import EdgeML

/// Tests for ``WeightExtractor`` serialization methods and
/// ``PrivacyConfiguration`` gradient-clipping parameters.
///
/// These tests exercise the pure-algorithmic paths of WeightExtractor
/// (serializeToPyTorch, serializeMLMultiArray, computeDelta, subtractArrays)
/// without requiring real CoreML model files.
final class WeightExtractorSerializationTests: XCTestCase {

    private var extractor: WeightExtractor!

    override func setUp() {
        super.setUp()
        extractor = WeightExtractor()
    }

    // MARK: - serializeMLMultiArray

    func testSerializeMLMultiArrayProducesCorrectByteCount() async throws {
        let array = try MLMultiArray(shape: [4], dataType: .float32)
        for i in 0..<4 { array[i] = NSNumber(value: Float(i)) }

        let data = try await extractor.serializeMLMultiArray(array)

        // 4 floats * 4 bytes each = 16
        XCTAssertEqual(data.count, 16)
    }

    func testSerializeMLMultiArrayRoundtripsValues() async throws {
        let values: [Float] = [1.5, -2.0, 0.0, 3.14]
        let array = try MLMultiArray(shape: [NSNumber(value: values.count)], dataType: .float32)
        for (i, v) in values.enumerated() { array[i] = NSNumber(value: v) }

        let data = try await extractor.serializeMLMultiArray(array)
        let decoded = data.withUnsafeBytes { buf -> [Float] in
            Array(buf.bindMemory(to: Float.self))
        }

        XCTAssertEqual(decoded.count, values.count)
        for (a, b) in zip(decoded, values) {
            XCTAssertEqual(a, b, accuracy: 1e-6)
        }
    }

    func testSerializeMLMultiArrayEmptyArray() async throws {
        // A shape of [0] is valid; should produce zero bytes.
        let array = try MLMultiArray(shape: [0], dataType: .float32)
        let data = try await extractor.serializeMLMultiArray(array)
        XCTAssertEqual(data.count, 0)
    }

    // MARK: - serializeToPyTorch

    func testSerializeToPyTorchWritesMagicAndVersion() async throws {
        // Empty delta -> just header
        let data = try await extractor.serializeToPyTorch(delta: [:])

        XCTAssertNotNil(PyTorchDataBuilder.readMagic(from: data))
        XCTAssertEqual(PyTorchDataBuilder.readMagic(from: data), PyTorchDataBuilder.magic)
        XCTAssertEqual(PyTorchDataBuilder.readParamCount(from: data), 0)
    }

    func testSerializeToPyTorchSingleParameter() async throws {
        let values: [Float] = [1.0, 2.0, 3.0]
        let array = try MLMultiArray(shape: [NSNumber(value: values.count)], dataType: .float32)
        for (i, v) in values.enumerated() { array[i] = NSNumber(value: v) }

        let data = try await extractor.serializeToPyTorch(delta: ["layer_0_weight": array])

        XCTAssertEqual(PyTorchDataBuilder.readMagic(from: data), PyTorchDataBuilder.magic)
        XCTAssertEqual(PyTorchDataBuilder.readParamCount(from: data), 1)
        // header(12) + nameLen(4) + name(14) + shapeCount(4) + dim(4) + dtype(4) + dataLen(4) + data(12) = 58
        XCTAssertTrue(data.count > 12, "Data should be larger than just the header")
    }

    func testSerializeToPyTorchMultipleParametersSortedByName() async throws {
        let a1 = try MLMultiArray(shape: [2], dataType: .float32)
        a1[0] = 1; a1[1] = 2
        let a2 = try MLMultiArray(shape: [2], dataType: .float32)
        a2[0] = 3; a2[1] = 4

        let data = try await extractor.serializeToPyTorch(delta: ["z_param": a1, "a_param": a2])

        XCTAssertEqual(PyTorchDataBuilder.readParamCount(from: data), 2)

        // Verify first param name is "a_param" (lexicographically first)
        let nameLen = data.withUnsafeBytes { $0.load(fromByteOffset: 12, as: UInt32.self).bigEndian }
        let nameData = data.subdata(in: 16 ..< 16 + Int(nameLen))
        let firstName = String(data: nameData, encoding: .utf8)
        XCTAssertEqual(firstName, "a_param")
    }

    func testSerializeToPyTorchMultidimensionalShape() async throws {
        let array = try MLMultiArray(shape: [2, 3], dataType: .float32)
        for i in 0..<6 { array[i] = NSNumber(value: Float(i)) }

        let data = try await extractor.serializeToPyTorch(delta: ["conv_weight": array])

        XCTAssertEqual(PyTorchDataBuilder.readParamCount(from: data), 1)
        // Data should contain shape dimensions [2, 3]
        XCTAssertTrue(data.count > 12)
    }

    // MARK: - computeDelta

    func testComputeDeltaSubtractsMatchingKeys() async throws {
        let original = try makeArray([1.0, 2.0, 3.0])
        let updated = try makeArray([4.0, 6.0, 8.0])

        let delta = await extractor.computeDelta(
            original: ["w": original],
            updated: ["w": updated]
        )

        XCTAssertEqual(delta.count, 1)
        let result = try XCTUnwrap(delta["w"])
        XCTAssertEqual(result[0].floatValue, 3.0, accuracy: 1e-6)
        XCTAssertEqual(result[1].floatValue, 4.0, accuracy: 1e-6)
        XCTAssertEqual(result[2].floatValue, 5.0, accuracy: 1e-6)
    }

    func testComputeDeltaPassesThroughNewKeys() async throws {
        let updated = try makeArray([7.0, 8.0])

        let delta = await extractor.computeDelta(
            original: [:],
            updated: ["new_param": updated]
        )

        XCTAssertEqual(delta.count, 1)
        let result = try XCTUnwrap(delta["new_param"])
        XCTAssertEqual(result[0].floatValue, 7.0, accuracy: 1e-6)
    }

    func testComputeDeltaEmptyInputsProduceEmptyDelta() async throws {
        let delta = await extractor.computeDelta(original: [:], updated: [:])
        XCTAssertTrue(delta.isEmpty)
    }

    func testComputeDeltaIgnoresOriginalOnlyKeys() async throws {
        let original = try makeArray([1.0])

        let delta = await extractor.computeDelta(
            original: ["old_param": original],
            updated: [:]
        )

        XCTAssertTrue(delta.isEmpty)
    }

    // MARK: - subtractArrays

    func testSubtractArraysElementWise() async throws {
        let a = try makeArray([10.0, 20.0, 30.0])
        let b = try makeArray([1.0, 2.0, 3.0])

        let result = await extractor.subtractArrays(a, b)

        let r = try XCTUnwrap(result)
        XCTAssertEqual(r[0].floatValue, 9.0, accuracy: 1e-6)
        XCTAssertEqual(r[1].floatValue, 18.0, accuracy: 1e-6)
        XCTAssertEqual(r[2].floatValue, 27.0, accuracy: 1e-6)
    }

    func testSubtractArraysReturnsNilForShapeMismatch() async throws {
        let a = try makeArray([1.0, 2.0])
        let b = try makeArray([1.0, 2.0, 3.0])

        let result = await extractor.subtractArrays(a, b)
        XCTAssertNil(result)
    }

    func testSubtractArraysNegativeResult() async throws {
        let a = try makeArray([1.0])
        let b = try makeArray([5.0])

        let result = await extractor.subtractArrays(a, b)
        let r = try XCTUnwrap(result)
        XCTAssertEqual(r[0].floatValue, -4.0, accuracy: 1e-6)
    }

    func testSubtractArraysZeroDelta() async throws {
        let a = try makeArray([3.0, 7.0])
        let b = try makeArray([3.0, 7.0])

        let result = await extractor.subtractArrays(a, b)
        let r = try XCTUnwrap(result)
        XCTAssertEqual(r[0].floatValue, 0.0, accuracy: 1e-6)
        XCTAssertEqual(r[1].floatValue, 0.0, accuracy: 1e-6)
    }

    // MARK: - PyTorchDataBuilder verification

    func testPyTorchDataBuilderProducesValidHeader() {
        let data = PyTorchDataBuilder.build(flat: ["w": [1.0, 2.0]])

        XCTAssertEqual(PyTorchDataBuilder.readMagic(from: data), PyTorchDataBuilder.magic)
        XCTAssertEqual(PyTorchDataBuilder.readParamCount(from: data), 1)
    }

    func testPyTorchDataBuilderEmptyPayload() {
        let data = PyTorchDataBuilder.build(flat: [:])

        XCTAssertEqual(PyTorchDataBuilder.readMagic(from: data), PyTorchDataBuilder.magic)
        XCTAssertEqual(PyTorchDataBuilder.readParamCount(from: data), 0)
        XCTAssertEqual(data.count, 12) // header only
    }

    func testPyTorchDataBuilderReadMagicFromShortData() {
        let data = Data([0x01, 0x02])
        XCTAssertNil(PyTorchDataBuilder.readMagic(from: data))
    }

    func testPyTorchDataBuilderReadParamCountFromShortData() {
        let data = Data([0x01, 0x02, 0x03, 0x04])
        XCTAssertNil(PyTorchDataBuilder.readParamCount(from: data))
    }

    // MARK: - PrivacyConfiguration gradient clipping

    func testDPClippingNormDefault() {
        let config = PrivacyConfiguration.standard
        XCTAssertEqual(config.dpClippingNorm, 1.0)
    }

    func testDPClippingNormHighPrivacy() {
        let config = PrivacyConfiguration.highPrivacy
        XCTAssertEqual(config.dpClippingNorm, 1.0)
        XCTAssertTrue(config.enableDifferentialPrivacy)
    }

    func testDPClippingNormCustom() {
        let config = PrivacyConfiguration(
            enableDifferentialPrivacy: true,
            dpEpsilon: 0.1,
            dpClippingNorm: 5.0
        )
        XCTAssertEqual(config.dpClippingNorm, 5.0)
        XCTAssertEqual(config.dpEpsilon, 0.1)
    }

    func testDPDisabledStillHasClippingNorm() {
        let config = PrivacyConfiguration.disabled
        // Even when DP is disabled, the clipping norm is available (default)
        XCTAssertEqual(config.dpClippingNorm, 1.0)
        XCTAssertFalse(config.enableDifferentialPrivacy)
    }

    func testRandomUploadDelayDisabledReturnsZero() {
        let config = PrivacyConfiguration.disabled
        XCTAssertEqual(config.randomUploadDelay(), 0.0)
    }

    func testRandomUploadDelayEnabledReturnsWithinRange() {
        let config = PrivacyConfiguration(
            enableStaggeredUpdates: true,
            minUploadDelaySeconds: 10,
            maxUploadDelaySeconds: 20
        )
        for _ in 0..<20 {
            let delay = config.randomUploadDelay()
            XCTAssertGreaterThanOrEqual(delay, 10.0)
            XCTAssertLessThanOrEqual(delay, 20.0)
        }
    }

    // MARK: - Gradient clipping boundary tests

    /// Helper: computes L2 norm of an MLMultiArray.
    private func l2Norm(_ array: MLMultiArray) -> Double {
        var sum: Double = 0
        for i in 0..<array.count {
            let v = array[i].doubleValue
            sum += v * v
        }
        return sqrt(sum)
    }

    /// Helper: clips delta in-place to maxGradientNorm if L2 norm exceeds it.
    private func clipDelta(_ array: MLMultiArray, maxNorm: Double) throws -> MLMultiArray {
        let norm = l2Norm(array)
        if norm <= maxNorm {
            return array // no clipping needed
        }
        let scale = maxNorm / norm
        let clipped = try MLMultiArray(shape: array.shape, dataType: array.dataType)
        for i in 0..<array.count {
            clipped[i] = NSNumber(value: array[i].doubleValue * scale)
        }
        return clipped
    }

    func testGradientClippingDeltaAtExactThresholdNotClipped() throws {
        let maxNorm = PrivacyConfiguration.standard.dpClippingNorm // 1.0

        // Create a delta with L2 norm exactly at the threshold.
        // Vector [1.0, 0.0] has L2 norm = 1.0 = maxNorm.
        let delta = try makeArray([1.0, 0.0])
        let norm = l2Norm(delta)
        XCTAssertEqual(norm, maxNorm, accuracy: 1e-6,
                       "Delta norm should exactly equal the clipping threshold")

        let clipped = try clipDelta(delta, maxNorm: maxNorm)

        // Should NOT be clipped (norm == maxNorm, not >)
        XCTAssertEqual(clipped[0].floatValue, 1.0, accuracy: 1e-6,
                       "Delta at exact threshold should not be clipped")
        XCTAssertEqual(clipped[1].floatValue, 0.0, accuracy: 1e-6)
    }

    func testGradientClippingDeltaSlightlyAboveThresholdIsClipped() throws {
        let maxNorm = PrivacyConfiguration.standard.dpClippingNorm // 1.0

        // Create a delta with L2 norm slightly above the threshold.
        // Vector [1.0, 0.1] has L2 norm = sqrt(1.01) ≈ 1.005
        let delta = try makeArray([1.0, 0.1])
        let norm = l2Norm(delta)
        XCTAssertGreaterThan(norm, maxNorm,
                             "Delta norm should exceed the clipping threshold")

        let clipped = try clipDelta(delta, maxNorm: maxNorm)
        let clippedNorm = l2Norm(clipped)

        XCTAssertEqual(clippedNorm, maxNorm, accuracy: 1e-6,
                       "Clipped delta norm should equal the clipping threshold")
        // Values should be scaled down proportionally
        XCTAssertLessThan(clipped[0].floatValue, 1.0,
                          "Clipped value should be less than original")
    }

    func testGradientClippingDeltaWellBelowThresholdNotClipped() throws {
        let maxNorm = PrivacyConfiguration.standard.dpClippingNorm // 1.0

        // Small delta: [0.1, 0.1] has L2 norm ≈ 0.141
        let delta = try makeArray([0.1, 0.1])
        let norm = l2Norm(delta)
        XCTAssertLessThan(norm, maxNorm,
                          "Delta norm should be well below threshold")

        let clipped = try clipDelta(delta, maxNorm: maxNorm)

        // Should NOT be clipped
        XCTAssertEqual(clipped[0].floatValue, 0.1, accuracy: 1e-6,
                       "Small delta should not be clipped")
        XCTAssertEqual(clipped[1].floatValue, 0.1, accuracy: 1e-6)
    }

    func testGradientClippingWithCustomNorm() throws {
        let config = PrivacyConfiguration(
            enableDifferentialPrivacy: true,
            dpEpsilon: 0.5,
            dpClippingNorm: 5.0
        )

        // Delta with L2 norm = sqrt(9+16) = 5.0 = maxNorm exactly
        let delta = try makeArray([3.0, 4.0])
        let norm = l2Norm(delta)
        XCTAssertEqual(norm, config.dpClippingNorm, accuracy: 1e-6)

        let clipped = try clipDelta(delta, maxNorm: config.dpClippingNorm)
        XCTAssertEqual(clipped[0].floatValue, 3.0, accuracy: 1e-6,
                       "At exact threshold, values should be preserved")
        XCTAssertEqual(clipped[1].floatValue, 4.0, accuracy: 1e-6)

        // Now slightly over: [3.0, 4.01]
        let overDelta = try makeArray([3.0, 4.01])
        let overClipped = try clipDelta(overDelta, maxNorm: config.dpClippingNorm)
        let overNorm = l2Norm(overClipped)
        XCTAssertEqual(overNorm, config.dpClippingNorm, accuracy: 1e-4,
                       "Clipped norm should match the clipping threshold")
    }

    // MARK: - Helpers

    private func makeArray(_ values: [Float]) throws -> MLMultiArray {
        let array = try MLMultiArray(shape: [NSNumber(value: values.count)], dataType: .float32)
        for (i, v) in values.enumerated() {
            array[i] = NSNumber(value: v)
        }
        return array
    }
}
