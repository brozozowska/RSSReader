import Testing
@testable import RSSReader

@Suite("Repositories / SwiftData Operation Instrumentation")
@MainActor
struct RepositoryOperationInstrumentationTests {
    @Test
    func feedInsertRecordsItsNestedUniquenessFetchAndSave() throws {
        let operations = SwiftDataRepositoryOperationCounter()
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(steps: []),
            feedRepositoryOperationRecorder: operations.record
        )

        _ = try harness.feedRepository.insert(
            Feed(url: "https://example.com/instrumented.xml", title: "Instrumented")
        )

        #expect(operations.fetchCount > 0)
        #expect(operations.saveCount > 0)
    }
}
