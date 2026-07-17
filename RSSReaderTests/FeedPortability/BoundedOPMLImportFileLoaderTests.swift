import Foundation
import Testing
@testable import RSSReader

@Suite("Feed Portability / Bounded OPML Import File Loader")
struct BoundedOPMLImportFileLoaderTests {
    @Test
    func acceptsRegularFileAtExactByteLimit() async throws {
        let maximumBytes = 256
        let fileURL = try makeTemporaryFile(
            data: makeOPMLData(byteCount: maximumBytes)
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        let plan = try await makeLoader(maximumBytes: maximumBytes).loadPreview(
            fileURL: fileURL,
            existingFeeds: [],
            existingFolders: []
        )

        #expect(plan.entries.isEmpty)
        #expect(plan.ignoredOutlineCount == 0)
    }

    @Test
    func rejectsDeclaredRegularFileOneByteOverLimitBeforeParsing() async throws {
        let maximumBytes = 256
        let fileURL = try makeTemporaryFile(
            data: makeOPMLData(byteCount: maximumBytes + 1)
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }

        do {
            _ = try await makeLoader(maximumBytes: maximumBytes).loadPreview(
                fileURL: fileURL,
                existingFeeds: [],
                existingFolders: []
            )
            Issue.record("Expected oversized OPML file to be rejected")
        } catch let violation as AppResourceBudgetViolation {
            #expect(violation == .compressedBodySizeExceeded(
                input: .opml,
                maximumBytes: Int64(maximumBytes),
                actualBytes: Int64(maximumBytes + 1)
            ))
        } catch {
            Issue.record("Expected OPML body-size violation, got \(error)")
        }
    }

    @Test
    func parentCancellationCancelsBoundedReadWorker() async throws {
        let maximumBytes = 1_048_576
        let fileURL = try makeTemporaryFile(
            data: makeOPMLData(byteCount: maximumBytes)
        )
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let loader = makeLoader(maximumBytes: maximumBytes, readChunkSize: 1)

        let task = Task {
            try await loader.loadPreview(
                fileURL: fileURL,
                existingFeeds: [],
                existingFolders: []
            )
        }
        try await Task.sleep(for: .milliseconds(10))
        task.cancel()

        do {
            _ = try await task.value
            Issue.record("Expected cancelled OPML load to throw CancellationError")
        } catch is CancellationError {
            return
        } catch {
            Issue.record("Expected CancellationError, got \(error)")
        }
    }

    private func makeLoader(
        maximumBytes: Int,
        readChunkSize: Int = 64 * 1024
    ) -> BoundedOPMLImportFileLoader {
        BoundedOPMLImportFileLoader(
            budget: RuntimeXMLInputBudget(
                body: RuntimeInputBodyBudget(
                    input: .opml,
                    maximumCompressedBodyBytes: Int64(maximumBytes),
                    allowedMIMETypes: ["application/xml"]
                ),
                maximumElementCount: 100,
                maximumDepth: 10,
                maximumEntryCount: 10
            ),
            readChunkSize: readChunkSize
        )
    }

    private func makeTemporaryFile(data: Data) throws -> URL {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("opml")
        try data.write(to: fileURL)
        return fileURL
    }

    private func makeOPMLData(byteCount: Int) -> Data {
        let prefix = "<opml><body>"
        let suffix = "</body></opml>"
        let commentPrefix = "<!--"
        let commentSuffix = "-->"
        let fixedByteCount = Data(
            (prefix + commentPrefix + commentSuffix + suffix).utf8
        ).count
        precondition(byteCount >= fixedByteCount)
        let padding = String(repeating: "x", count: byteCount - fixedByteCount)
        let data = Data(
            (prefix + commentPrefix + padding + commentSuffix + suffix).utf8
        )
        precondition(data.count == byteCount)
        return data
    }
}
