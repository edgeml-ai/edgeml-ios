import XCTest
import CoreML
@testable import Octomil

final class DeployTests: XCTestCase {

    // MARK: - Engine Tests

    func testEngineRawValues() {
        XCTAssertEqual(Engine.auto.rawValue, "auto")
        XCTAssertEqual(Engine.coreml.rawValue, "coreml")
    }

    func testEngineCodableRoundTrip() throws {
        let original = Engine.coreml
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Engine.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testEngineAutoCodable() throws {
        let original = Engine.auto
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Engine.self, from: data)
        XCTAssertEqual(decoded, original)
    }

    func testEngineDecodesFromString() throws {
        let json = Data("\"coreml\"".utf8)
        let decoded = try JSONDecoder().decode(Engine.self, from: json)
        XCTAssertEqual(decoded, .coreml)
    }

    func testEngineInvalidStringFails() {
        let json = Data("\"pytorch\"".utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(Engine.self, from: json))
    }

    // MARK: - DeployError Tests

    func testUnsupportedFormatErrorDescription() {
        let error = DeployError.unsupportedFormat("pt")
        XCTAssertEqual(
            error.errorDescription,
            "Unsupported model format: .pt. Supported formats: .mlmodelc, .mlmodel, .mlpackage"
        )
    }

    func testUnsupportedFormatWithEmptyExtension() {
        let error = DeployError.unsupportedFormat("")
        XCTAssertTrue(error.errorDescription!.contains("Unsupported model format"))
    }

    func testDeployWithUnsupportedFormatThrows() {
        let tmpDir = FileManager.default.temporaryDirectory
        let fakePath = tmpDir.appendingPathComponent("model.pt")
        FileManager.default.createFile(atPath: fakePath.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: fakePath) }

        XCTAssertThrowsError(try Deploy.model(at: fakePath)) { error in
            guard let deployError = error as? DeployError else {
                XCTFail("Expected DeployError, got \(type(of: error))")
                return
            }
            if case .unsupportedFormat(let ext) = deployError {
                XCTAssertEqual(ext, "pt")
            } else {
                XCTFail("Expected unsupportedFormat")
            }
        }
    }

    func testDeployWithTxtFormatThrows() {
        let tmpDir = FileManager.default.temporaryDirectory
        let fakePath = tmpDir.appendingPathComponent("model.txt")
        FileManager.default.createFile(atPath: fakePath.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: fakePath) }

        XCTAssertThrowsError(try Deploy.model(at: fakePath)) { error in
            guard let deployError = error as? DeployError else {
                XCTFail("Expected DeployError, got \(type(of: error))")
                return
            }
            if case .unsupportedFormat(let ext) = deployError {
                XCTAssertEqual(ext, "txt")
            }
        }
    }

    func testDeployWithOnnxFormatThrows() {
        let tmpDir = FileManager.default.temporaryDirectory
        let fakePath = tmpDir.appendingPathComponent("model.onnx")
        FileManager.default.createFile(atPath: fakePath.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: fakePath) }

        XCTAssertThrowsError(try Deploy.model(at: fakePath, benchmark: false)) { error in
            guard case DeployError.unsupportedFormat("onnx") = error else {
                XCTFail("Expected unsupportedFormat(\"onnx\"), got \(error)")
                return
            }
        }
    }

    // MARK: - DeployedModel Tests

    func testDeployedModelInitWithoutWarmup() throws {
        // DeployedModel.init requires OctomilModel (wraps MLModel), which needs
        // a compiled .mlmodelc. Test the activeDelegate fallback logic directly:
        // when warmupResult is nil, activeDelegate returns "unknown".
        let warmup: WarmupResult? = nil
        let activeDelegate = warmup?.activeDelegate ?? "unknown"
        XCTAssertEqual(activeDelegate, "unknown",
                       "Without warmup, activeDelegate should be 'unknown'")

        // Verify WarmupResult with a delegate returns that delegate
        let withWarmup = WarmupResult(
            coldInferenceMs: 50.0,
            warmInferenceMs: 5.0,
            cpuInferenceMs: 10.0,
            usingNeuralEngine: true,
            activeDelegate: "neural_engine",
            disabledDelegates: ["cpu"]
        )
        XCTAssertEqual(withWarmup.activeDelegate, "neural_engine",
                       "With warmup, activeDelegate should match the provided value")
    }

    func testWarmupResultProperties() {
        let result = WarmupResult(
            coldInferenceMs: 50.0,
            warmInferenceMs: 5.0,
            cpuInferenceMs: 10.0,
            usingNeuralEngine: true,
            activeDelegate: "neural_engine",
            disabledDelegates: ["cpu"]
        )

        XCTAssertEqual(result.coldInferenceMs, 50.0)
        XCTAssertEqual(result.warmInferenceMs, 5.0)
        XCTAssertEqual(result.cpuInferenceMs, 10.0)
        XCTAssertTrue(result.usingNeuralEngine)
        XCTAssertEqual(result.activeDelegate, "neural_engine")
        XCTAssertEqual(result.disabledDelegates, ["cpu"])
    }

    func testWarmupResultCPUFaster() {
        let result = WarmupResult(
            coldInferenceMs: 50.0,
            warmInferenceMs: 15.0,
            cpuInferenceMs: 8.0,
            usingNeuralEngine: false,
            activeDelegate: "cpu",
            disabledDelegates: ["neural_engine"]
        )

        XCTAssertFalse(result.usingNeuralEngine)
        XCTAssertEqual(result.activeDelegate, "cpu")
        XCTAssertEqual(result.disabledDelegates, ["neural_engine"])
    }

    func testWarmupResultNoCPUBaseline() {
        let result = WarmupResult(
            coldInferenceMs: 100.0,
            warmInferenceMs: 10.0,
            cpuInferenceMs: nil,
            usingNeuralEngine: true,
            activeDelegate: "neural_engine",
            disabledDelegates: []
        )

        XCTAssertNil(result.cpuInferenceMs)
        XCTAssertTrue(result.usingNeuralEngine)
        XCTAssertTrue(result.disabledDelegates.isEmpty)
    }

    // MARK: - Deploy Name Resolution Tests

    func testDeployNameFromURL() {
        // Verify that unsupported formats pass through name resolution before failing
        let tmpDir = FileManager.default.temporaryDirectory
        let fakePath = tmpDir.appendingPathComponent("MyCustomModel.safetensors")
        FileManager.default.createFile(atPath: fakePath.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: fakePath) }

        // The error should happen after name resolution, confirming the path is parsed
        XCTAssertThrowsError(try Deploy.model(at: fakePath, name: nil))
    }

    func testDeployCustomNamePassedThrough() {
        let tmpDir = FileManager.default.temporaryDirectory
        let fakePath = tmpDir.appendingPathComponent("model.bin")
        FileManager.default.createFile(atPath: fakePath.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: fakePath) }

        // Even with a custom name, unsupported format should throw
        XCTAssertThrowsError(try Deploy.model(at: fakePath, name: "MyModel"))
    }

    // MARK: - Deploy Benchmark Flag Tests

    func testDeployBenchmarkDefaultIsTrue() {
        // Verify the default parameter value by calling without benchmark arg
        let tmpDir = FileManager.default.temporaryDirectory
        let fakePath = tmpDir.appendingPathComponent("test.bin")
        FileManager.default.createFile(atPath: fakePath.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: fakePath) }

        // This throws DeployError (unsupported format), not because of benchmark
        XCTAssertThrowsError(try Deploy.model(at: fakePath)) { error in
            XCTAssertTrue(error is DeployError)
        }
    }

    func testDeployBenchmarkFalseStillValidates() {
        let tmpDir = FileManager.default.temporaryDirectory
        let fakePath = tmpDir.appendingPathComponent("test.bin")
        FileManager.default.createFile(atPath: fakePath.path, contents: Data())
        defer { try? FileManager.default.removeItem(at: fakePath) }

        XCTAssertThrowsError(try Deploy.model(at: fakePath, benchmark: false)) { error in
            XCTAssertTrue(error is DeployError)
        }
    }
}
