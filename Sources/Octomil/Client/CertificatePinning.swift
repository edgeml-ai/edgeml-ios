import Foundation
import CommonCrypto
import os.log

/// Delegate that validates server certificates against pinned SHA-256 public key hashes.
///
/// When `pinnedHashes` is non-empty, the delegate extracts the server's public key,
/// computes its SHA-256 hash, and checks it against the provided pins. If no pins
/// are configured, validation falls through to the system default (development mode).
public final class CertificatePinningDelegate: NSObject, URLSessionDelegate, Sendable {

    /// SHA-256 hashes of the DER-encoded public keys that the server is allowed to present.
    /// Each string should be a base64-encoded SHA-256 hash (e.g., from `openssl`).
    private let pinnedHashes: [String]
    private let logger = Logger(subsystem: "ai.octomil.sdk", category: "CertificatePinning")

    /// Creates a new pinning delegate.
    /// - Parameter pinnedHashes: Base64-encoded SHA-256 hashes of allowed public keys.
    ///   Pass an empty array to fall back to system validation.
    public init(pinnedHashes: [String] = []) {
        self.pinnedHashes = pinnedHashes
        super.init()
    }

    // MARK: - URLSessionDelegate

    public func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let serverTrust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // No pins configured — fall back to system default validation.
        guard !pinnedHashes.isEmpty else {
            completionHandler(.performDefaultHandling, nil)
            return
        }

        // Evaluate the trust object using system root certificates first.
        var error: CFError?
        let trustValid = SecTrustEvaluateWithError(serverTrust, &error)
        guard trustValid else {
            logger.warning("Server trust evaluation failed: \(String(describing: error))")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        // Extract the server's leaf certificate public key and check its hash.
        if let serverCertificate = SecTrustGetCertificateAtIndex(serverTrust, 0),
           let publicKey = SecCertificateCopyKey(serverCertificate),
           let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, nil) as Data? {

            let hash = sha256(data: publicKeyData)
            let hashBase64 = hash.base64EncodedString()

            if pinnedHashes.contains(hashBase64) {
                completionHandler(.useCredential, URLCredential(trust: serverTrust))
                return
            }

            logger.error("Certificate pin mismatch. Server hash: \(hashBase64)")
            completionHandler(.cancelAuthenticationChallenge, nil)
            return
        }

        logger.error("Unable to extract public key from server certificate")
        completionHandler(.cancelAuthenticationChallenge, nil)
    }

    // MARK: - Hashing

    /// Computes the SHA-256 hash of the given data.
    static func sha256(data: Data) -> Data {
        var hash = [UInt8](repeating: 0, count: Int(CC_SHA256_DIGEST_LENGTH))
        data.withUnsafeBytes { buffer in
            _ = CC_SHA256(buffer.baseAddress, CC_LONG(buffer.count), &hash)
        }
        return Data(hash)
    }

    private func sha256(data: Data) -> Data {
        Self.sha256(data: data)
    }
}
