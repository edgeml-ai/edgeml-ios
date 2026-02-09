import Foundation

// MARK: - Gradient Clipping

extension WeightExtractor {

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
        for index in floats.indices {
            floats[index] *= scale
        }

        // Rebuild the data with clipped values
        return rebuildWeightsData(original: weightsData, clippedFloats: floats)
    }

    /// Extracts all Float32 values from PyTorch-format weight data.
    fileprivate func extractFloats(from data: Data) -> [Float] {
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
            for floatIndex in 0..<floatCount {
                let floatOffset = offset + floatIndex * 4
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
    fileprivate func rebuildWeightsData(original: Data, clippedFloats: [Float]) -> Data {
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
            for elementIndex in 0..<floatCount {
                guard floatIndex < clippedFloats.count else { break }
                let floatOffset = offset + elementIndex * 4
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

    fileprivate func readUInt32BigEndian(_ data: Data, at offset: Int) -> UInt32 {
        return data.withUnsafeBytes { ptr -> UInt32 in
            let bound = ptr.baseAddress!.advanced(by: offset)
            return UInt32(bigEndian: bound.assumingMemoryBound(to: UInt32.self).pointee)
        }
    }
}
