import Foundation
import Testing
@testable import RSSReader

@Suite("Infrastructure / Disposable Cache Migration")
struct DisposableCacheMigrationServiceTests {
    @Test
    func oldDirectoryIsRemovedAndRepeatedCleanupIsIdempotent() throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryDirectory() }
        try fixture.createDirectory(named: DisposableCacheMigrationService.legacyFeedIconDirectoryName)

        let firstResult = try fixture.service.removeLegacyFeedIconCacheDirectory()
        let secondResult = try fixture.service.removeLegacyFeedIconCacheDirectory()

        #expect(firstResult)
        #expect(secondResult == false)
        #expect(fixture.directoryExists(named: DisposableCacheMigrationService.legacyFeedIconDirectoryName) == false)
    }

    @Test
    func newDirectoryIsPreservedWhenLegacyDirectoryIsAbsent() throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryDirectory() }
        let currentDirectoryName = FeedIconDiskCache.directoryName
        try fixture.createDirectory(named: currentDirectoryName, data: Data("current".utf8))

        let result = try fixture.service.removeLegacyFeedIconCacheDirectory()

        #expect(result == false)
        #expect(try fixture.data(inDirectoryNamed: currentDirectoryName) == Data("current".utf8))
    }

    @Test
    func oldDirectoryIsRemovedWithoutTouchingNewDirectoryWhenBothExist() throws {
        let fixture = try makeFixture()
        defer { fixture.removeTemporaryDirectory() }
        let legacyDirectoryName = DisposableCacheMigrationService.legacyFeedIconDirectoryName
        let currentDirectoryName = FeedIconDiskCache.directoryName
        try fixture.createDirectory(named: legacyDirectoryName, data: Data("legacy".utf8))
        try fixture.createDirectory(named: currentDirectoryName, data: Data("current".utf8))

        let result = try fixture.service.removeLegacyFeedIconCacheDirectory()

        #expect(result)
        #expect(fixture.directoryExists(named: legacyDirectoryName) == false)
        #expect(try fixture.data(inDirectoryNamed: currentDirectoryName) == Data("current".utf8))
    }

    private func makeFixture() throws -> DisposableCacheMigrationFixture {
        let cachesDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: cachesDirectoryURL,
            withIntermediateDirectories: true
        )
        return DisposableCacheMigrationFixture(cachesDirectoryURL: cachesDirectoryURL)
    }
}

private struct DisposableCacheMigrationFixture {
    let cachesDirectoryURL: URL
    let service: DisposableCacheMigrationService

    init(cachesDirectoryURL: URL) {
        self.cachesDirectoryURL = cachesDirectoryURL
        service = DisposableCacheMigrationService(cachesDirectoryURL: cachesDirectoryURL)
    }

    func createDirectory(named name: String, data: Data = Data("cache".utf8)) throws {
        let directoryURL = cachesDirectoryURL.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true
        )
        try data.write(to: directoryURL.appendingPathComponent("entry"))
    }

    func directoryExists(named name: String) -> Bool {
        FileManager.default.fileExists(
            atPath: cachesDirectoryURL.appendingPathComponent(name, isDirectory: true).path
        )
    }

    func data(inDirectoryNamed name: String) throws -> Data {
        try Data(
            contentsOf: cachesDirectoryURL
                .appendingPathComponent(name, isDirectory: true)
                .appendingPathComponent("entry")
        )
    }

    func removeTemporaryDirectory() {
        try? FileManager.default.removeItem(at: cachesDirectoryURL)
    }
}
