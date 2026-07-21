import Foundation

nonisolated struct DisposableCacheMigrationService {
    static let legacyFeedIconDirectoryName = "RSSReaderSourceIcons"

    private let cachesDirectoryURL: URL
    private let fileManager: FileManager

    init(
        cachesDirectoryURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        self.fileManager = fileManager
        self.cachesDirectoryURL = cachesDirectoryURL
            ?? fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    }

    @discardableResult
    func removeLegacyFeedIconCacheDirectory() throws -> Bool {
        let legacyDirectoryURL = cachesDirectoryURL.appendingPathComponent(
            Self.legacyFeedIconDirectoryName,
            isDirectory: true
        )
        guard fileManager.fileExists(atPath: legacyDirectoryURL.path) else {
            return false
        }

        try fileManager.removeItem(at: legacyDirectoryURL)
        return true
    }
}
