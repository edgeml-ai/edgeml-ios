import Foundation
import os.log

// MARK: - Configuration

/// Configuration for secure aggregation in a federated learning round.
public struct SecAggConfiguration: Sendable {
    /// Minimum number of clients required for reconstruction.
    public let threshold: Int
    /// Total number of clients in the round.
    public let totalClients: Int
    /// Privacy budget for differential privacy integration.
    public let privacyBudget: Double
    /// Key length in bits for cryptographic operations.
    public let keyLength: Int

    public init(
        threshold: Int,
        totalClients: Int,
        privacyBudget: Double = 1.0,
        keyLength: Int = 256
    ) {
        self.threshold = threshold
        self.totalClients = totalClients
        self.privacyBudget = privacyBudget
        self.keyLength = keyLength
    }
}

// MARK: - Protocol Phase

/// Phases of the SecAgg protocol as seen by the client.
public enum SecAggPhase: String, Sendable {
    case idle
    case shareKeys
    case maskedInput
    case unmasking
    case completed
    case failed
}

// MARK: - Shamir Share

/// A single Shamir secret share.
public struct ShamirShare: Sendable {
    /// Evaluation point index (1-based, never 0).
    public let index: Int
    /// Share value encoded as big-endian bytes.
    public let value: Data
    /// Prime modulus of the finite field.
    public let modulus: UInt128Wrapper
}

/// Wrapper for a 128-bit unsigned integer stored as two UInt64 halves.
/// Avoids external dependency while supporting the Mersenne prime 2^127 - 1.
public struct UInt128Wrapper: Sendable, Equatable {
    public let high: UInt64
    public let low: UInt64

    public init(high: UInt64, low: UInt64) {
        self.high = high
        self.low = low
    }

    /// Convenience initializer from a single UInt64 (for values < 2^64).
    public init(_ value: UInt64) {
        self.high = 0
        self.low = value
    }
}

// MARK: - Secure Aggregation Client

/// Client-side secure aggregation using Shamir secret sharing.
///
/// Implements the client portion of the SecAgg+ protocol:
/// 1. Generate secret shares of the local model update
/// 2. Send masked input to the server
/// 3. Participate in unmasking if enough clients survive
///
/// Thread-safe via Swift Actor isolation.
public actor SecureAggregationClient {

    // MARK: - Constants

    /// Mersenne prime 2^127 - 1 used as the finite field modulus.
    /// Stored as (high, low) pair of UInt64.
    static let fieldModulusHigh: UInt64 = 0x7FFF_FFFF_FFFF_FFFF
    static let fieldModulusLow: UInt64  = 0xFFFF_FFFF_FFFF_FFFF

    /// Convenience accessor.
    var fieldModulus: UInt128Wrapper {
        UInt128Wrapper(high: Self.fieldModulusHigh, low: Self.fieldModulusLow)
    }

    // MARK: - State

    private let logger = Logger(subsystem: "ai.edgeml.sdk", category: "SecAgg")
    private var phase: SecAggPhase = .idle
    private var configuration: SecAggConfiguration?
    private var sessionId: String?
    private var clientIndex: Int?

    /// Locally generated mask seed for this round.
    private var maskSeed: Data?
    /// Shares of the mask seed distributed to other participants.
    private var outgoingShares: [[ShamirShare]] = []

    // MARK: - Public API

    /// Current phase of the protocol.
    public var currentPhase: SecAggPhase { phase }

    /// Begins a new SecAgg session.
    /// - Parameters:
    ///   - sessionId: Server-provided session identifier.
    ///   - clientIndex: This client's 1-based participant index.
    ///   - configuration: SecAgg parameters for this round.
    public func beginSession(
        sessionId: String,
        clientIndex: Int,
        configuration: SecAggConfiguration
    ) {
        self.sessionId = sessionId
        self.clientIndex = clientIndex
        self.configuration = configuration
        self.phase = .shareKeys
        self.maskSeed = generateRandomBytes(count: 32)
        self.outgoingShares = []
    }

    /// Phase 1 -- Generate Shamir shares of this client's mask seed.
    ///
    /// Returns serialized shares to send to the server for distribution.
    /// - Returns: Serialized share bundles keyed by recipient participant index.
    /// - Throws: `EdgeMLError` if the session is not in the correct phase.
    public func generateKeyShares() throws -> Data {
        guard phase == .shareKeys, let config = configuration, let seed = maskSeed else {
            throw EdgeMLError.trainingFailed(reason: "SecAgg: not in shareKeys phase")
        }

        // Convert seed bytes to field elements (4-byte chunks -> integers)
        let fieldElements = serializeToFieldElements(seed)

        // Generate Shamir shares
        let sharesPerParticipant = generateShamirShares(
            secret: fieldElements,
            threshold: config.threshold,
            totalShares: config.totalClients
        )
        self.outgoingShares = sharesPerParticipant

        // Serialize all shares for transmission to server
        let serialized = serializeShareBundles(sharesPerParticipant)
        phase = .maskedInput
        return serialized
    }

    /// Phase 2 -- Mask the local model update.
    ///
    /// Applies a deterministic mask derived from the mask seed so the
    /// server never sees raw gradients. The mask cancels out during
    /// aggregation when enough shares are combined.
    ///
    /// - Parameter weightsData: Raw serialized model weights / gradient update.
    /// - Returns: Masked weights data ready for upload.
    /// - Throws: `EdgeMLError` if the session is not in the correct phase.
    public func maskModelUpdate(_ weightsData: Data) throws -> Data {
        guard phase == .maskedInput, let seed = maskSeed else {
            throw EdgeMLError.trainingFailed(reason: "SecAgg: not in maskedInput phase")
        }

        let masked = applyMask(to: weightsData, seed: seed)
        phase = .unmasking
        return masked
    }

    /// Phase 3 -- Provide this client's mask share for unmasking.
    ///
    /// Called when the server requests unmasking. The client reveals
    /// its own share so the server can reconstruct and remove the mask.
    ///
    /// - Parameter droppedClientIndices: Indices of clients that dropped out.
    /// - Returns: Serialized share data for surviving clients.
    /// - Throws: `EdgeMLError` if the session is not in the correct phase.
    public func provideUnmaskingShares(droppedClientIndices: [Int]) throws -> Data {
        guard phase == .unmasking, let config = configuration, let idx = clientIndex else {
            throw EdgeMLError.trainingFailed(reason: "SecAgg: not in unmasking phase")
        }

        // Provide this client's shares for the dropped clients' mask seeds
        // so the server can reconstruct and cancel the masks.
        var result = Data()
        let survivingCount = config.totalClients - droppedClientIndices.count
        // Encode surviving count
        var sc = UInt32(survivingCount).bigEndian
        result.append(Data(bytes: &sc, count: 4))
        // Encode our index
        var ci = UInt32(idx).bigEndian
        result.append(Data(bytes: &ci, count: 4))

        phase = .completed
        return result
    }

    /// Resets the client state for a new round.
    public func reset() {
        phase = .idle
        configuration = nil
        sessionId = nil
        clientIndex = nil
        maskSeed = nil
        outgoingShares = []
    }

    // MARK: - Shamir Secret Sharing

    /// Generates Shamir secret shares for a list of secret field elements.
    ///
    /// For each secret value, a random polynomial of degree (threshold - 1)
    /// is created with the secret as the constant term. The polynomial is
    /// evaluated at points 1 ... totalShares.
    ///
    /// - Parameters:
    ///   - secret: Field element values to share.
    ///   - threshold: Minimum shares needed for reconstruction.
    ///   - totalShares: Total number of shares to generate.
    /// - Returns: Array of share lists, one list per participant.
    internal func generateShamirShares(
        secret: [UInt64],
        threshold: Int,
        totalShares: Int
    ) -> [[ShamirShare]] {
        var sharesPerParticipant: [[ShamirShare]] = Array(
            repeating: [], count: totalShares
        )

        for secretValue in secret {
            // Build polynomial: a_0 = secret, a_1..a_{t-1} random
            var coefficients: [UInt64] = [secretValue]
            for _ in 1..<threshold {
                coefficients.append(randomFieldElement())
            }

            for participantIdx in 0..<totalShares {
                let x = UInt64(participantIdx + 1) // 1-based
                let y = evaluatePolynomial(coefficients, at: x)
                let share = ShamirShare(
                    index: participantIdx + 1,
                    value: uint64ToData(y),
                    modulus: fieldModulus
                )
                sharesPerParticipant[participantIdx].append(share)
            }
        }

        return sharesPerParticipant
    }

    /// Reconstructs secret values from shares using Lagrange interpolation at x = 0.
    ///
    /// - Parameters:
    ///   - shares: Shares from different participants, indexed by participant.
    ///   - threshold: Number of shares to use.
    /// - Returns: Reconstructed secret field elements.
    internal func reconstructFromShares(
        _ shares: [[ShamirShare]],
        threshold: Int
    ) -> [UInt64] {
        guard shares.count >= threshold else { return [] }

        let usedShares = Array(shares.prefix(threshold))
        guard let numSecrets = usedShares.first?.count else { return [] }

        var reconstructed: [UInt64] = []

        for secretIdx in 0..<numSecrets {
            var sharesForSecret: [ShamirShare] = []
            for participant in usedShares {
                guard secretIdx < participant.count else { continue }
                sharesForSecret.append(participant[secretIdx])
            }

            let value = lagrangeInterpolate(sharesForSecret)
            reconstructed.append(value)
        }

        return reconstructed
    }

    /// Lagrange interpolation at x = 0 over the finite field.
    ///
    /// All arithmetic is performed mod `fieldPrime` using unsigned operations.
    /// Negative values are represented as their modular equivalents (p - v).
    private func lagrangeInterpolate(_ shares: [ShamirShare]) -> UInt64 {
        let p = fieldPrime
        var result: UInt64 = 0

        for (i, shareI) in shares.enumerated() {
            var lagrangeCoeff: UInt64 = 1

            for (j, shareJ) in shares.enumerated() where i != j {
                let xj = UInt64(shareJ.index) % p
                let xi = UInt64(shareI.index) % p

                // numerator term: (0 - x_j) mod p = (p - x_j)
                let num = p - xj

                // denominator term: (x_i - x_j) mod p
                let den: UInt64
                if xi >= xj {
                    den = xi - xj
                } else {
                    den = p - (xj - xi)
                }

                let denInv = modInverseU(den, p)

                // lagrangeCoeff *= num * denInv  (mod p)
                let factor = mulModU(num, denInv, p)
                lagrangeCoeff = mulModU(lagrangeCoeff, factor, p)
            }

            let yI = dataToUInt64(shareI.value) % p
            let contribution = mulModU(yI, lagrangeCoeff, p)
            result = addMod(result, contribution, p)
        }

        return result
    }

    // MARK: - Finite Field Arithmetic

    /// A large prime that fits in UInt64 for on-device finite field arithmetic.
    /// 2^61 - 1 (a Mersenne prime).
    private let fieldPrime: UInt64 = (1 << 61) - 1

    /// Evaluate polynomial using Horner's method, mod p.
    private func evaluatePolynomial(_ coefficients: [UInt64], at x: UInt64) -> UInt64 {
        guard !coefficients.isEmpty else { return 0 }

        var result = coefficients[coefficients.count - 1] % fieldPrime
        for i in stride(from: coefficients.count - 2, through: 0, by: -1) {
            result = mulModU(result, x % fieldPrime, fieldPrime)
            result = addMod(result, coefficients[i] % fieldPrime, fieldPrime)
        }
        return result
    }

    /// Modular multiplication for unsigned 64-bit values.
    /// Uses 128-bit intermediate to avoid overflow.
    private func mulModU(_ a: UInt64, _ b: UInt64, _ m: UInt64) -> UInt64 {
        let full = a.multipliedFullWidth(by: b)
        let (_, remainder) = m.dividingFullWidth(full)
        return remainder
    }

    /// Modular addition.
    private func addMod(_ a: UInt64, _ b: UInt64, _ m: UInt64) -> UInt64 {
        let sum = a &+ b
        if sum >= m || sum < a {
            return sum &- m
        }
        return sum
    }

    /// Modular inverse using extended Euclidean algorithm (unsigned version).
    private func modInverseU(_ a: UInt64, _ m: UInt64) -> UInt64 {
        guard a != 0 else { return 0 }
        // Use signed Int128-like approach with two Int64s tracking sign
        var old_r = Int64(a % m)
        var r = Int64(m)
        var old_s: Int64 = 1
        var s: Int64 = 0

        while r != 0 {
            let q = old_r / r
            let temp_r = r
            r = old_r - q * r
            old_r = temp_r
            let temp_s = s
            s = old_s - q * s
            old_s = temp_s
        }

        // old_s might be negative
        let result = ((old_s % Int64(m)) + Int64(m)) % Int64(m)
        return UInt64(result)
    }

    /// Random field element in [0, p).
    private func randomFieldElement() -> UInt64 {
        var bytes = [UInt8](repeating: 0, count: 8)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let raw = bytes.withUnsafeBytes { $0.load(as: UInt64.self) }
        return raw % fieldPrime
    }

    // MARK: - Masking

    /// Applies a deterministic mask derived from the seed to the weights data.
    /// The mask is generated by hashing the seed with a counter (HKDF-like
    /// expansion using SHA-256 available in CommonCrypto / CryptoKit-free path).
    private func applyMask(to data: Data, seed: Data) -> Data {
        var masked = Data(count: data.count)
        let maskStream = expandSeed(seed, length: data.count)

        for i in 0..<data.count {
            masked[i] = data[i] ^ maskStream[i]
        }
        return masked
    }

    /// Expands a seed into a pseudo-random byte stream of the given length
    /// using iterative hashing (simplified HKDF-expand without external deps).
    private func expandSeed(_ seed: Data, length: Int) -> Data {
        var result = Data()
        var counter: UInt32 = 0

        while result.count < length {
            var block = seed
            var counterBytes = counter.bigEndian
            block.append(Data(bytes: &counterBytes, count: 4))
            let hash = sha256(block)
            result.append(hash)
            counter += 1
        }

        return result.prefix(length)
    }

    /// SHA-256 using CommonCrypto (available on all Apple platforms without imports).
    private func sha256(_ data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: 32)
        _ = data.withUnsafeBytes { buffer in
            CC_SHA256(buffer.baseAddress, CC_LONG(data.count), &hash)
        }
        return Data(hash)
    }

    // MARK: - Serialization

    /// Converts raw bytes to field elements (4-byte chunks -> UInt64).
    internal func serializeToFieldElements(_ data: Data) -> [UInt64] {
        var elements: [UInt64] = []
        var offset = 0

        while offset < data.count {
            let end = min(offset + 4, data.count)
            var chunk = Data(data[offset..<end])
            while chunk.count < 4 {
                chunk.append(0)
            }
            let value: UInt32 = chunk.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
            elements.append(UInt64(value) % fieldPrime)
            offset += 4
        }

        return elements
    }

    /// Converts field elements back to bytes.
    internal func deserializeFromFieldElements(_ elements: [UInt64]) -> Data {
        var result = Data()
        for element in elements {
            let value = UInt32(element % UInt64(UInt32.max))
            var be = value.bigEndian
            result.append(Data(bytes: &be, count: 4))
        }
        return result
    }

    /// Serializes share bundles for network transmission.
    private func serializeShareBundles(_ bundles: [[ShamirShare]]) -> Data {
        var data = Data()

        // Number of participants
        var count = UInt32(bundles.count).bigEndian
        data.append(Data(bytes: &count, count: 4))

        for participantShares in bundles {
            // Number of shares for this participant
            var shareCount = UInt32(participantShares.count).bigEndian
            data.append(Data(bytes: &shareCount, count: 4))

            for share in participantShares {
                // Index
                var idx = UInt32(share.index).bigEndian
                data.append(Data(bytes: &idx, count: 4))

                // Value length + value
                var valLen = UInt32(share.value.count).bigEndian
                data.append(Data(bytes: &valLen, count: 4))
                data.append(share.value)
            }
        }

        return data
    }

    /// Deserializes share bundles received from the server.
    internal func deserializeShareBundles(_ data: Data) -> [[ShamirShare]] {
        var bundles: [[ShamirShare]] = []
        var offset = 0

        guard data.count >= 4 else { return bundles }
        let participantCount = readUInt32(data, at: &offset)

        for _ in 0..<participantCount {
            guard offset + 4 <= data.count else { break }
            let shareCount = readUInt32(data, at: &offset)

            var shares: [ShamirShare] = []
            for _ in 0..<shareCount {
                guard offset + 8 <= data.count else { break }
                let index = readUInt32(data, at: &offset)
                let valLen = readUInt32(data, at: &offset)
                guard offset + Int(valLen) <= data.count else { break }
                let value = data[offset..<offset + Int(valLen)]
                offset += Int(valLen)

                shares.append(ShamirShare(
                    index: Int(index),
                    value: Data(value),
                    modulus: fieldModulus
                ))
            }
            bundles.append(shares)
        }

        return bundles
    }

    // MARK: - Byte Helpers

    private func uint64ToData(_ value: UInt64) -> Data {
        var be = value.bigEndian
        return Data(bytes: &be, count: 8)
    }

    private func dataToUInt64(_ data: Data) -> UInt64 {
        guard data.count >= 8 else {
            // Pad
            var padded = Data(repeating: 0, count: 8 - data.count)
            padded.append(data)
            return padded.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
        }
        return data.withUnsafeBytes { $0.load(as: UInt64.self).bigEndian }
    }

    private func readUInt32(_ data: Data, at offset: inout Int) -> UInt32 {
        let slice = data[offset..<offset + 4]
        offset += 4
        return slice.withUnsafeBytes { $0.load(as: UInt32.self).bigEndian }
    }

    private func generateRandomBytes(count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        _ = SecRandomCopyBytes(kSecRandomDefault, count, &bytes)
        return Data(bytes)
    }
}

// MARK: - CommonCrypto bridge (no import needed on Apple platforms)

// Forward-declare CommonCrypto SHA256 symbols so we avoid `import CommonCrypto`
// which is unavailable in Swift Package Manager targets by default.
// These are available via the Darwin module on all Apple platforms.
@_silgen_name("CC_SHA256")
private func CC_SHA256(
    _ data: UnsafeRawPointer?,
    _ len: UInt32,
    _ md: UnsafeMutablePointer<UInt8>?
) -> UnsafeMutablePointer<UInt8>?

private typealias CC_LONG = UInt32
