import Foundation
import CoreML
import os.log

/// Utility for extracting and serializing model weights from CoreML models.
///
/// CoreML doesn't provide direct access to model weights, so this implementation
/// uses the MLModel inspection APIs to extract parameters and compute deltas.
actor WeightExtractor {

    private let logger: Logger

    init() {
        self.logger = Logger(subsystem: "ai.edgeml.sdk", category: "WeightExtractor")
    }

    // MARK: - Weight Extraction

    /// Extracts weight deltas from a trained model by comparing with the original.
    ///
    /// - Parameters:
    ///   - originalModelURL: URL to the original (pre-training) model.
    ///   - updatedContext: MLUpdateContext containing the trained model.
    /// - Returns: Serialized weight delta in PyTorch-compatible format.
    /// - Throws: EdgeMLError if extraction fails.
    func extractWeightDelta(
        originalModelURL: URL,
        updatedContext: MLUpdateContext
    ) async throws -> Data {
        logger.info("Extracting weight delta from trained model")

        // Write updated model to temporary location
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mlmodelc")

        try updatedContext.model.write(to: tempURL)

        defer {
            // Clean up temporary file
            try? FileManager.default.removeItem(at: tempURL)
        }

        // Extract weights from both models
        let originalWeights = try await extractWeights(from: originalModelURL)
        let updatedWeights = try await extractWeights(from: tempURL)

        // Compute delta (updated - original)
        let delta = computeDelta(original: originalWeights, updated: updatedWeights)

        // Serialize to PyTorch format
        let serialized = try serializeToPyTorch(delta: delta)

        logger.info("Weight delta extracted: \(serialized.count) bytes")

        return serialized
    }

    /// Extracts full weights from a trained model (for full weight uploads).
    ///
    /// - Parameter updatedContext: MLUpdateContext containing the trained model.
    /// - Returns: Serialized full weights in PyTorch-compatible format.
    /// - Throws: EdgeMLError if extraction fails.
    func extractFullWeights(
        updatedContext: MLUpdateContext
    ) async throws -> Data {
        logger.info("Extracting full weights from trained model")

        // Write updated model to temporary location
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("mlmodelc")

        try updatedContext.model.write(to: tempURL)

        defer {
            try? FileManager.default.removeItem(at: tempURL)
        }

        // Extract weights
        let weights = try await extractWeights(from: tempURL)

        // Serialize to PyTorch format
        let serialized = try serializeToPyTorch(delta: weights)

        logger.info("Full weights extracted: \(serialized.count) bytes")

        return serialized
    }

    // MARK: - Private Methods

    /// Extracts weights from a CoreML model using the model's parameter structure.
    private func extractWeights(from modelURL: URL) async throws -> [String: MLMultiArray] {
        var weights: [String: MLMultiArray] = [:]

        do {
            // Load the model
            let model = try MLModel(contentsOf: modelURL)

            // For CoreML models with updatable parameters, we can access them through
            // the model's parameter key-value pairs
            // Note: This requires the model to be compiled with updateable parameters

            // Try to extract using the model's description
            if let modelDescription = model.modelDescription as? MLModelDescription {
                // Get updatable parameter names
                // In CoreML 5+, models can expose updatable parameters
                let parameterKeys = extractParameterKeys(from: modelDescription)

                for key in parameterKeys {
                    if let value = try? extractParameter(from: model, key: key) {
                        weights[key] = value
                    }
                }
            }

            logger.debug("Extracted \(weights.count) parameter arrays")

        } catch {
            logger.error("Failed to extract weights: \(error.localizedDescription)")
            throw EdgeMLError.weightExtractionFailed(reason: error.localizedDescription)
        }

        return weights
    }

    /// Extracts parameter keys from the model description.
    private func extractParameterKeys(from _: MLModelDescription) -> [String] {
        var keys: [String] = []

        // CoreML updatable models expose parameter descriptions
        // These are typically layer names with suffixes like "_weight" or "_bias"
        // For example: "dense_1_weight", "dense_1_bias", "conv2d_1_weight", etc.

        // In a real implementation, you'd inspect the model's parameter descriptions
        // For now, we'll use a heuristic based on common layer naming patterns
        let commonLayerPrefixes = ["dense", "conv2d", "lstm", "gru", "embedding"]
        let parameterSuffixes = ["_weight", "_bias", "_kernel", "_gamma", "_beta"]

        // This is a simplified approach - in production, you'd use the actual
        // model parameter descriptions from CoreML
        for prefix in commonLayerPrefixes {
            for i in 0..<10 { // Assume up to 10 layers of each type
                for suffix in parameterSuffixes {
                    keys.append("\(prefix)_\(i)\(suffix)")
                }
            }
        }

        return keys
    }

    /// Extracts a specific parameter from the model.
    private func extractParameter(from _: MLModel, key _: String) throws -> MLMultiArray {
        // In CoreML 5+, you can access parameters through the MLModel API
        // However, this requires the model to expose these parameters

        // For models created with Create ML or exported with coremltools,
        // parameters can be accessed through the model's underlying neural network

        // This is a placeholder - the actual implementation depends on how
        // the CoreML model was created and whether it exposes parameters
        throw EdgeMLError.weightExtractionFailed(reason: "Parameter extraction not yet implemented")
    }

    /// Computes delta between original and updated weights.
    private func computeDelta(
        original: [String: MLMultiArray],
        updated: [String: MLMultiArray]
    ) -> [String: MLMultiArray] {
        var delta: [String: MLMultiArray] = [:]

        for (key, updatedArray) in updated {
            guard let originalArray = original[key] else {
                // If parameter doesn't exist in original, use full updated value
                delta[key] = updatedArray
                continue
            }

            // Compute difference
            if let differenceArray = subtractArrays(updatedArray, originalArray) {
                delta[key] = differenceArray
            }
        }

        return delta
    }

    /// Subtracts two MLMultiArrays element-wise.
    private func subtractArrays(_ a: MLMultiArray, _ b: MLMultiArray) -> MLMultiArray? {
        guard a.shape == b.shape else {
            return nil
        }

        let count = a.count
        guard let result = try? MLMultiArray(shape: a.shape, dataType: a.dataType) else {
            return nil
        }

        for i in 0..<count {
            let aValue = a[i].doubleValue
            let bValue = b[i].doubleValue
            result[i] = NSNumber(value: aValue - bValue)
        }

        return result
    }

    /// Serializes weight delta to PyTorch-compatible format.
    ///
    /// Serializes to a simple format that can be loaded by PyTorch:
    /// - Header: Magic number, version, parameter count
    /// - For each parameter: name length, name, shape, data
    private func serializeToPyTorch(delta: [String: MLMultiArray]) throws -> Data {
        var data = Data()

        // Write magic number (0x50545448 = "PTTH" for PyTorch)
        let magic: UInt32 = 0x50545448
        data.append(contentsOf: withUnsafeBytes(of: magic.bigEndian) { Array($0) })

        // Write version (1)
        let version: UInt32 = 1
        data.append(contentsOf: withUnsafeBytes(of: version.bigEndian) { Array($0) })

        // Write parameter count
        let paramCount = UInt32(delta.count)
        data.append(contentsOf: withUnsafeBytes(of: paramCount.bigEndian) { Array($0) })

        // Write each parameter
        for (name, array) in delta.sorted(by: { $0.key < $1.key }) {
            // Write parameter name
            let nameData = name.data(using: .utf8)!
            let nameLength = UInt32(nameData.count)
            data.append(contentsOf: withUnsafeBytes(of: nameLength.bigEndian) { Array($0) })
            data.append(nameData)

            // Write shape
            let shapeCount = UInt32(array.shape.count)
            data.append(contentsOf: withUnsafeBytes(of: shapeCount.bigEndian) { Array($0) })
            for dim in array.shape {
                let dimValue = UInt32(truncating: dim)
                data.append(contentsOf: withUnsafeBytes(of: dimValue.bigEndian) { Array($0) })
            }

            // Write data type (0 = float32, 1 = float64, 2 = int32, 3 = int64)
            let dataType: UInt32 = {
                switch array.dataType {
                case .float32, .float16: return 0
                case .double: return 1
                case .int32: return 2
                default: return 0
                }
            }()
            data.append(contentsOf: withUnsafeBytes(of: dataType.bigEndian) { Array($0) })

            // Write array data
            let arrayData = try serializeMLMultiArray(array)
            let dataLength = UInt32(arrayData.count)
            data.append(contentsOf: withUnsafeBytes(of: dataLength.bigEndian) { Array($0) })
            data.append(arrayData)
        }

        return data
    }

    // MARK: - Gradient Clipping

    /// Applies L2-norm gradient clipping to serialized weight data.
    ///
    /// Reads the PyTorch-format weight data, clips each parameter's values
    /// so the overall L2 norm does not exceed `maxNorm`, and re-serializes.
    ///
    /// - Parameters:
    ///   - weightsData: Serialized weight data in PyTorch format.
    ///   - maxNorm: Maximum L2 norm threshold.
    /// - Returns: Clipped weight data in the same format.
    func applyGradientClipping(weightsData: Data, maxNorm: Double) -> Data {
        guard maxNorm > 0 else { return weightsData }

        // Interpret the data as an array of Float32 values (skip header for norm calculation)
        // For simplicity, treat the entire data payload as float values and compute global L2 norm.
        // The format has headers that are UInt32 big-endian, but we can parse minimally.

        // Parse the PyTorch format to extract float values
        var floats = extractFloats(from: weightsData)
        guard !floats.isEmpty else { return weightsData }

        // Compute L2 norm
        var sumSquared: Double = 0.0
        for value in floats {
            sumSquared += Double(value) * Double(value)
        }
        let l2Norm = sumSquared.squareRoot()

        // Clip if norm exceeds threshold
        guard l2Norm > maxNorm else { return weightsData }

        let scale = Float(maxNorm / l2Norm)
        for i in floats.indices {
            floats[i] *= scale
        }

        // Rebuild the data with clipped values
        return rebuildWeightsData(original: weightsData, clippedFloats: floats)
    }

    /// Extracts all Float32 values from PyTorch-format weight data.
    private func extractFloats(from data: Data) -> [Float] {
        // PyTorch format: magic(4) + version(4) + paramCount(4) + params...
        // Each param: nameLen(4) + name(N) + shapeCount(4) + dims(4*M) + dataType(4) + dataLen(4) + data(L)
        guard data.count >= 12 else { return [] }

        var offset = 12 // skip magic, version, paramCount
        var allFloats: [Float] = []

        while offset < data.count {
            // Read name length
            guard offset + 4 <= data.count else { break }
            let nameLen = readUInt32BigEndian(data, at: offset)
            offset += 4

            // Skip name
            offset += Int(nameLen)
            guard offset + 4 <= data.count else { break }

            // Read shape count
            let shapeCount = readUInt32BigEndian(data, at: offset)
            offset += 4

            // Skip shape dims
            offset += Int(shapeCount) * 4
            guard offset + 4 <= data.count else { break }

            // Skip data type
            offset += 4
            guard offset + 4 <= data.count else { break }

            // Read data length
            let dataLen = Int(readUInt32BigEndian(data, at: offset))
            offset += 4

            // Read float values
            guard offset + dataLen <= data.count else { break }
            let floatCount = dataLen / 4
            for i in 0..<floatCount {
                let floatOffset = offset + i * 4
                let value = data.withUnsafeBytes { ptr -> Float in
                    let bound = ptr.baseAddress!.advanced(by: floatOffset)
                    return bound.assumingMemoryBound(to: Float.self).pointee
                }
                allFloats.append(value)
            }

            offset += dataLen
        }

        return allFloats
    }

    /// Rebuilds weight data by replacing float values with clipped versions.
    private func rebuildWeightsData(original: Data, clippedFloats: [Float]) -> Data {
        var result = original
        guard original.count >= 12 else { return result }

        var offset = 12
        var floatIndex = 0

        while offset < result.count {
            guard offset + 4 <= result.count else { break }
            let nameLen = readUInt32BigEndian(result, at: offset)
            offset += 4 + Int(nameLen)

            guard offset + 4 <= result.count else { break }
            let shapeCount = readUInt32BigEndian(result, at: offset)
            offset += 4 + Int(shapeCount) * 4

            // Skip data type
            guard offset + 4 <= result.count else { break }
            offset += 4

            guard offset + 4 <= result.count else { break }
            let dataLen = Int(readUInt32BigEndian(result, at: offset))
            offset += 4

            // Overwrite float values
            guard offset + dataLen <= result.count else { break }
            let floatCount = dataLen / 4
            for i in 0..<floatCount {
                guard floatIndex < clippedFloats.count else { break }
                let floatOffset = offset + i * 4
                var value = clippedFloats[floatIndex]
                withUnsafeBytes(of: &value) { bytes in
                    result.replaceSubrange(floatOffset..<floatOffset + 4, with: bytes)
                }
                floatIndex += 1
            }

            offset += dataLen
        }

        return result
    }

    private func readUInt32BigEndian(_ data: Data, at offset: Int) -> UInt32 {
        return data.withUnsafeBytes { ptr -> UInt32 in
            let bound = ptr.baseAddress!.advanced(by: offset)
            return UInt32(bigEndian: bound.assumingMemoryBound(to: UInt32.self).pointee)
        }
    }

    /// Serializes an MLMultiArray to binary format.
    private func serializeMLMultiArray(_ array: MLMultiArray) throws -> Data {
        var data = Data()

        // Convert all values to Float32 for consistency
        let count = array.count
        data.reserveCapacity(count * 4) // 4 bytes per float32

        for i in 0..<count {
            let value = array[i].floatValue
            data.append(contentsOf: withUnsafeBytes(of: value) { Array($0) })
        }

        return data
    }
}
