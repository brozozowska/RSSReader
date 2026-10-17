import CryptoKit
import Foundation

nonisolated protocol ArticleImageDiskCaching: Sendable {
    func data(for url: URL) async throws -> Data?
    func data(for url: URL, maximumBytes: Int64) async throws -> Data?
    func insert(_ data: Data, for url: URL) async throws
    func removeData(for url: URL) async throws
}

actor ArticleImageDiskCache: ArticleImageDiskCaching {
    static let shared = ArticleImageDiskCache()

    private let directoryURL: URL
    private let capacityLimit: Int64
    private let fileManager: FileManager
    private let dateProvider: @Sendable () -> Date

    init(
        directoryURL: URL? = nil,
        capacityLimit: Int64 = 200 * 1024 * 1024,
        fileManager: FileManager = .default,
        dateProvider: @escaping @Sendable () -> Date = Date.init
    ) {
        self.directoryURL = directoryURL ?? Self.defaultDirectoryURL(fileManager: fileManager)
        self.capacityLimit = capacityLimit
        self.fileManager = fileManager
        self.dateProvider = dateProvider
    }

    func data(for url: URL) throws -> Data? {
        let fileURL = fileURL(for: url)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let data = try Data(contentsOf: fileURL)
        try touch(fileURL)
        return data
    }

    func data(for url: URL, maximumBytes: Int64) throws -> Data? {
        precondition(maximumBytes > 0)
        precondition(maximumBytes <= Int64(Int.max))
        try Task.checkCancellation()

        let fileURL = fileURL(for: url)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard resourceValues.isRegularFile == true else {
            try fileManager.removeItem(at: fileURL)
            return nil
        }

        if let fileSize = resourceValues.fileSize, Int64(fileSize) > maximumBytes {
            try fileManager.removeItem(at: fileURL)
            return nil
        }

        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer { try? fileHandle.close() }

        var data = Data()
        data.reserveCapacity(min(resourceValues.fileSize ?? 0, Int(maximumBytes)))

        while true {
            try Task.checkCancellation()
            let remainingBytes = maximumBytes - Int64(data.count)
            let readCount = remainingBytes >= Int64(64 * 1024)
                ? 64 * 1024
                : Int(remainingBytes) + 1
            let chunk = try fileHandle.read(upToCount: readCount) ?? Data()
            guard chunk.isEmpty == false else { break }

            data.append(chunk)
            guard Int64(data.count) <= maximumBytes else {
                try fileManager.removeItem(at: fileURL)
                return nil
            }
        }

        try Task.checkCancellation()
        try touch(fileURL)
        return data
    }

    func insert(_ data: Data, for url: URL) throws {
        try prepareDirectoryIfNeeded()

        let fileURL = fileURL(for: url)
        try data.write(to: fileURL, options: .atomic)
        try touch(fileURL)
        try enforceCapacityLimit()
    }

    func removeData(for url: URL) throws {
        let fileURL = fileURL(for: url)
        guard fileManager.fileExists(atPath: fileURL.path) else { return }
        try fileManager.removeItem(at: fileURL)
    }

    func removeAll() throws {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return
        }

        let fileURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: nil
        )

        for fileURL in fileURLs {
            try fileManager.removeItem(at: fileURL)
        }
    }

    func isEmpty() throws -> Bool {
        try cacheEntries().isEmpty
    }

    private static func defaultDirectoryURL(fileManager: FileManager) -> URL {
        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        return cachesDirectory.appendingPathComponent("RSSReaderArticleImages", isDirectory: true)
    }

    private func prepareDirectoryIfNeeded() throws {
        guard fileManager.fileExists(atPath: directoryURL.path) == false else {
            return
        }

        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
    }

    private func fileURL(for url: URL) -> URL {
        directoryURL.appendingPathComponent(Self.cacheKey(for: url), isDirectory: false)
    }

    private static func cacheKey(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.absoluteString.utf8))
        let key = digest.map { String(format: "%02x", $0) }.joined()
        return "\(key).image"
    }

    private func touch(_ fileURL: URL) throws {
        try fileManager.setAttributes(
            [.modificationDate: dateProvider()],
            ofItemAtPath: fileURL.path
        )
    }

    private func enforceCapacityLimit() throws {
        let entries = try cacheEntries()
        var totalSize = entries.reduce(Int64(0)) { $0 + $1.size }

        for entry in entries.sorted(by: { $0.lastAccessedAt < $1.lastAccessedAt }) where totalSize > capacityLimit {
            try fileManager.removeItem(at: entry.fileURL)
            totalSize -= entry.size
        }
    }

    private func cacheEntries() throws -> [ArticleImageDiskCacheEntry] {
        guard fileManager.fileExists(atPath: directoryURL.path) else {
            return []
        }

        let resourceKeys: Set<URLResourceKey> = [
            .contentModificationDateKey,
            .fileSizeKey,
            .isRegularFileKey
        ]
        let fileURLs = try fileManager.contentsOfDirectory(
            at: directoryURL,
            includingPropertiesForKeys: Array(resourceKeys)
        )

        return try fileURLs.compactMap { fileURL in
            let resourceValues = try fileURL.resourceValues(forKeys: resourceKeys)
            guard resourceValues.isRegularFile == true else { return nil }

            return ArticleImageDiskCacheEntry(
                fileURL: fileURL,
                size: Int64(resourceValues.fileSize ?? 0),
                lastAccessedAt: resourceValues.contentModificationDate ?? .distantPast
            )
        }
    }
}

private struct ArticleImageDiskCacheEntry {
    let fileURL: URL
    let size: Int64
    let lastAccessedAt: Date
}
