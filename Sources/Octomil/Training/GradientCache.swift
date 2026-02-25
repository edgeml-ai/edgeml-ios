import Foundation
import os.log

/// File-based cache for gradient updates that haven't been submitted to the server.
///
/// Persists ``GradientCacheEntry`` values as JSON files in Application Support,
/// following the same pattern as ``EventQueue``. Entries survive app restarts
/// and can be retried when the network becomes available.
public actor GradientCache {

    // MARK: - Properties

    private let cacheDir: URL
    private let jsonEncoder: JSONEncoder
    private let jsonDecoder: JSONDecoder
    private let logger: Logger

    // MARK: - Initialization

    /// Creates a gradient cache with the default directory.
    public init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        self.cacheDir = appSupport.appendingPathComponent("octomil_gradient_cache", isDirectory: true)
        self.jsonEncoder = JSONEncoder()
        self.jsonEncoder.dateEncodingStrategy = .iso8601
        self.jsonDecoder = JSONDecoder()
        self.jsonDecoder.dateDecodingStrategy = .iso8601
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "GradientCache")

        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    /// Creates a gradient cache with a custom directory (for testing).
    internal init(cacheDir: URL) {
        self.cacheDir = cacheDir
        self.jsonEncoder = JSONEncoder()
        self.jsonEncoder.dateEncodingStrategy = .iso8601
        self.jsonDecoder = JSONDecoder()
        self.jsonDecoder.dateDecodingStrategy = .iso8601
        self.logger = Logger(subsystem: "ai.octomil.sdk", category: "GradientCache")

        try? FileManager.default.createDirectory(at: cacheDir, withIntermediateDirectories: true)
    }

    // MARK: - Public Methods

    /// Stores a gradient cache entry.
    ///
    /// If an entry with the same `roundId` already exists, it is overwritten.
    ///
    /// - Parameter entry: The gradient entry to cache.
    public func store(_ entry: GradientCacheEntry) {
        do {
            let data = try jsonEncoder.encode(entry)
            let fileURL = fileURL(for: entry.roundId)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.warning("Failed to cache gradient for round \(entry.roundId): \(error.localizedDescription)")
        }
    }

    /// Retrieves a cached gradient entry by round ID.
    ///
    /// - Parameter roundId: The round identifier.
    /// - Returns: The cached entry, or nil if not found.
    public func retrieve(roundId: String) -> GradientCacheEntry? {
        let fileURL = fileURL(for: roundId)
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }
        return try? jsonDecoder.decode(GradientCacheEntry.self, from: data)
    }

    /// Returns all pending (unsubmitted) gradient entries, sorted by creation date.
    ///
    /// - Returns: Array of unsubmitted cached entries.
    public func pendingEntries() -> [GradientCacheEntry] {
        guard let files = try? cacheFiles() else { return [] }
        return files.compactMap { url -> GradientCacheEntry? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            return try? jsonDecoder.decode(GradientCacheEntry.self, from: data)
        }
        .filter { !$0.submitted }
        .sorted { $0.createdAt < $1.createdAt }
    }

    /// Marks a cached entry as submitted.
    ///
    /// Re-reads the entry, sets `submitted = true`, and writes it back.
    ///
    /// - Parameter roundId: The round identifier to mark.
    /// - Returns: `true` if the entry was found and marked, `false` otherwise.
    @discardableResult
    public func markSubmitted(roundId: String) -> Bool {
        guard var entry = retrieve(roundId: roundId) else { return false }
        entry.submitted = true
        store(entry)
        return true
    }

    /// Removes all entries older than the given date.
    ///
    /// - Parameter date: Entries with `createdAt` before this date are removed.
    /// - Returns: Number of entries purged.
    @discardableResult
    public func purgeOlderThan(_ date: Date) -> Int {
        guard let files = try? cacheFiles() else { return 0 }
        var purged = 0
        for url in files {
            guard let data = try? Data(contentsOf: url),
                  let entry = try? jsonDecoder.decode(GradientCacheEntry.self, from: data) else {
                continue
            }
            if entry.createdAt < date {
                try? FileManager.default.removeItem(at: url)
                purged += 1
            }
        }
        return purged
    }

    /// Removes a cached gradient entry.
    ///
    /// - Parameter roundId: The round identifier to remove.
    public func remove(roundId: String) {
        let fileURL = fileURL(for: roundId)
        try? FileManager.default.removeItem(at: fileURL)
    }

    /// Removes all cached entries.
    public func clear() {
        guard let files = try? cacheFiles() else { return }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Returns the number of cached entries.
    public func count() -> Int {
        (try? cacheFiles().count) ?? 0
    }

    // MARK: - Private

    private func fileURL(for roundId: String) -> URL {
        cacheDir.appendingPathComponent("\(roundId).json")
    }

    private func cacheFiles() throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: cacheDir,
            includingPropertiesForKeys: nil
        ).filter { $0.pathExtension == "json" }
    }
}
