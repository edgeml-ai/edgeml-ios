import Foundation

/// Builds valid PyTorch-format ``Data`` blobs for testing ``WeightExtractor``
/// serialization / deserialization round-trips.
///
/// The format mirrors the one written by ``WeightExtractor.serializeToPyTorch``:
/// ```
/// [magic: UInt32 BE] [version: UInt32 BE] [param_count: UInt32 BE]
/// For each parameter:
///   [name_len: UInt32 BE] [name: UTF-8] [shape_count: UInt32 BE] [dims: UInt32 BE ...]
///   [data_type: UInt32 BE] [data_len: UInt32 BE] [float32 values ...]
/// ```
enum PyTorchDataBuilder {

    /// Magic number matching ``WeightExtractor``.
    static let magic: UInt32 = 0x50545448

    /// Builds a complete PyTorch-format payload from a dictionary of named
    /// parameter arrays (keyed by parameter name, values are flat Float arrays
    /// paired with their shape).
    static func build(parameters: [String: (shape: [Int], values: [Float])]) -> Data {
        var data = Data()

        appendUInt32(&data, magic)
        appendUInt32(&data, 1) // version
        appendUInt32(&data, UInt32(parameters.count))

        for (name, param) in parameters.sorted(by: { $0.key < $1.key }) {
            // name
            let nameBytes = Data(name.utf8)
            appendUInt32(&data, UInt32(nameBytes.count))
            data.append(nameBytes)

            // shape
            appendUInt32(&data, UInt32(param.shape.count))
            for dim in param.shape {
                appendUInt32(&data, UInt32(dim))
            }

            // data type (0 = float32)
            appendUInt32(&data, 0)

            // array data
            var arrayData = Data()
            for value in param.values {
                var v = value
                arrayData.append(Data(bytes: &v, count: 4))
            }
            appendUInt32(&data, UInt32(arrayData.count))
            data.append(arrayData)
        }

        return data
    }

    /// Convenience: build from a ``[String: [Float]]`` dictionary, inferring
    /// a flat 1-D shape from the array length.
    static func build(flat parameters: [String: [Float]]) -> Data {
        var params: [String: (shape: [Int], values: [Float])] = [:]
        for (name, values) in parameters {
            params[name] = (shape: [values.count], values: values)
        }
        return build(parameters: params)
    }

    // MARK: - Reading helpers

    /// Reads the magic number from PyTorch-format data. Returns nil if data is
    /// too short.
    static func readMagic(from data: Data) -> UInt32? {
        guard data.count >= 4 else { return nil }
        return data.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }

    /// Reads the parameter count from PyTorch-format data.
    static func readParamCount(from data: Data) -> UInt32? {
        guard data.count >= 12 else { return nil }
        return data.withUnsafeBytes { $0.load(fromByteOffset: 8, as: UInt32.self).bigEndian }
    }

    // MARK: - Private

    private static func appendUInt32(_ data: inout Data, _ value: UInt32) {
        data.append(contentsOf: withUnsafeBytes(of: value.bigEndian) { Array($0) })
    }
}
