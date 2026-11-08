import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Queries / Reader-visible Search")
@MainActor
struct ReaderVisibleSearchTests {
    private func index(html: String? = nil, text: String? = nil, summary: String? = nil) -> String {
        ArticleSearchableTextPolicy.materialize(title: "Article", summary: summary, contentHTML: html, contentText: text, author: "Writer")
    }

    @Test(arguments: ["summary", "contentText", "contentHTML"])
    func rssMarkupDoesNotCreateMatches(field: String) {
        let html = "<p>Visible <a href='https://hidden.invalid/destinationtoken' rel='noopener nofollow'>link</a></p>"
        let result = index(html: field == "contentHTML" ? html : nil,
                           text: field == "contentText" ? html : nil,
                           summary: field == "summary" ? html : nil)
        #expect(!result.localizedCaseInsensitiveContains("open"))
        #expect(!result.contains("destinationtoken"))
        #expect(result.contains("Visible link"))
    }

    @Test
    func readerSourcePrecedenceAndFieldBoundaries() {
        let result = index(html: "<p>Chosen body</p>", text: "Discarded fallback", summary: "Unused summary")
        #expect(result.contains("Chosen body"))
        #expect(!result.contains("Discarded"))
        #expect(!result.contains("Unused"))
        #expect(!result.contains("Article Writer"))
        #expect(!result.contains("Writer Chosen"))
        let blocks = index(html: "<p>Alpha</p><p>Beta</p><table><tr><td>Gamma</td><td>Delta</td></tr></table>")
        for word in ["Alpha", "Beta", "Gamma", "Delta"] { #expect(blocks.contains(word)) }
        for phrase in ["Alpha Beta", "Gamma Delta"] { #expect(!blocks.contains(phrase)) }
    }

    @Test
    func allSemanticReaderTextIncludingCollapsedContentIsSearchable() {
        let result = index(html: """
        <h2>Headingtoken</h2><p>Inline <strong>boldtoken</strong> <a href='https://invisible.invalid'>labeltoken</a></p>
        <ul><li>Listtoken</li></ul><dl><dt>Termtoken</dt><dd>Definitiontoken</dd></dl>
        <blockquote>Quotetoken</blockquote><figure><figcaption>Captiontoken</figcaption></figure>
        <table><thead><tr><th>Headertoken</th><th>Otherheader</th></tr></thead><tbody><tr><td>Celltoken</td><td>Othercell</td></tr></tbody></table>
        <details><summary>Disclosuretoken</summary><p>Collapsedtoken</p><aside>Asidetoken</aside></details>
        <pre><code>literal &lt;a rel="noopener"&gt; &lt;!-- codecomment --&gt;</code></pre>
        <p>JAMA Network Open &amp; Café</p><!-- hiddentoken -->
        <script>scriptsecret</script><style>.csssecret { color: red }</style>
        """)
        for token in ["Headingtoken", "boldtoken", "labeltoken", "Listtoken", "Termtoken", "Definitiontoken",
                      "Quotetoken", "Captiontoken", "Headertoken", "Celltoken", "Disclosuretoken", "Collapsedtoken",
                      "Asidetoken", "noopener", "codecomment", "JAMA Network Open & Café"] {
            #expect(result.contains(token), "Missing visible token: \(token)")
        }
        for token in ["invisible.invalid", "hiddentoken", "scriptsecret", "csssecret"] {
            #expect(!result.contains(token), "Invisible token leaked: \(token)")
        }
    }

    @Test
    func longUnicodeTextAndOuterEscapingRemainComplete() {
        let prefix = String(repeating: "Юникод 👨‍👩‍👧‍👦 ", count: 8_000)
        let result = index(html: "&lt;p&gt;" + prefix + "NeedleAtEnd&lt;/p&gt;")
        #expect(result.contains("NeedleAtEnd"))
        #expect(result.contains(prefix.trimmingCharacters(in: .whitespaces)))
        let candidate = makeArticleSearchCandidateDTO(feedTitle: "Open   Feed", title: "Title", summary: nil,
                                                      contentText: prefix + "Cafe\u{301} reader")
        for query in ["open feed", "Café   reader", "title"] {
            let scope = ArticleSearchScope(normalizedQuery: ArticleSearchScope.normalizedSearchText(query), selection: .inbox, sidebarArticleFilter: .allItems)
            #expect(scope.contains(candidate))
        }
    }

    @Test
    func maintenanceResumesFromSavedRowsAndPreservesPayloadAndState() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let context = harness.modelContainer.mainContext
        let feed = Feed(url: "https://fixture.invalid/rss", title: "Feed")
        context.insert(feed)
        var ids: [UUID] = []
        for number in 0..<35 {
            let article = Article(feedID: feed.id, feedTitle: "Feed", externalID: "\(number)", url: "https://fixture.invalid/\(number)",
                                  title: "Article \(number)", contentText: "<p>Visible body</p>", searchableText: "old noopener")
            context.insert(article)
            ids.append(article.id)
        }
        let state = ArticleState(articleExternalID: "0", feedID: feed.id, isRead: true, isStarred: true, isHidden: true)
        context.insert(state)
        try context.save()
        let stateTimestamp = state.updatedAt
        enum Stop: Error { case interrupted }
        let first = ArticleSearchIndexMaintenance(container: harness.modelContainer, checkpoint: { count in
            if count == 3 { throw Stop.interrupted }
        })
        first.start()
        await #expect(throws: Stop.self) { try await first.waitUntilReady() }
        let rows = try context.fetch(FetchDescriptor<Article>())
        #expect(rows.filter { $0.searchableText.hasPrefix(ArticleSearchableTextPolicy.formatPrefix) }.count == 3)
        let restart = ArticleSearchIndexMaintenance(container: harness.modelContainer)
        restart.start()
        try await restart.waitUntilReady()
        let updated = try context.fetch(FetchDescriptor<Article>())
        #expect(Set(updated.map(\.id)) == Set(ids))
        #expect(updated.allSatisfy { $0.contentText == "<p>Visible body</p>" && $0.searchableText.contains("Visible body") && !$0.searchableText.contains("noopener") })
        // No old text survives a completed run; no feed refetch or source mutation.
        #expect(updated.allSatisfy { $0.author == nil && $0.archivedAt == nil })
        #expect(state.isRead && state.isStarred && state.isHidden)
        #expect(state.updatedAt == stateTimestamp)
        let savedIndex = updated[0].searchableText
        _ = try harness.articleStateRepository.upsert(feedID: feed.id, articleExternalID: updated[0].externalID,
                                                      update: ArticleStateUpsert(isRead: true, isStarred: true))
        #expect(updated[0].searchableText == savedIndex)

    }

    @Test
    func queryCancellationDoesNotCancelSharedMaintenance() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let context = harness.modelContainer.mainContext
        let feed = Feed(url: "https://fixture.invalid/rss", title: "Feed")
        context.insert(feed)
        let article = Article(feedID: feed.id, feedTitle: "Feed", externalID: "old", url: "", title: "Visible Needle", searchableText: "old")
        context.insert(article)
        try context.save()
        let entered = AsyncTestGate()
        let release = AsyncTestGate()
        defer { release.release() }
        let maintenance = ArticleSearchIndexMaintenance(container: harness.modelContainer, checkpoint: { _ in
            entered.release()
            try await release.wait("release maintenance checkpoint")
        })
        maintenance.start()
        try await entered.wait("first index checkpoint saved")
        let query = DefaultArticleQueryService(articleRepository: harness.articleRepository,
                                              articleStateRepository: harness.articleStateRepository,
                                              feedRepository: harness.feedRepository, indexMaintenance: maintenance)
        let request = ArticleSearchRequest(selection: .unread, sidebarArticleFilter: .allItems,
                                           query: "needle", sortMode: .publishedAtDescending)
        let cancelled = Task { try await query.fetchArticleSearchSnapshot(request) }
        try await waitUntil("query registered for index readiness") { maintenance.waitingQueryCount == 1 }
        cancelled.cancel()
        await #expect(throws: CancellationError.self) { _ = try await cancelled.value }
        #expect(maintenance.waitingQueryCount == 0)
        release.release()
        try await maintenance.waitUntilReady()
        let snapshot = try await query.fetchArticleSearchSnapshot(request)
        #expect(snapshot.articles.map(\.id) == [article.id])
    }

    @Test
    func persistedMaintenanceCheckpointSurvivesContainerRecreation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("reader-search-\(UUID())")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let schema = Schema([Article.self, ArticleState.self])
        let configuration = ModelConfiguration(schema: schema, url: directory.appendingPathComponent("store"), cloudKitDatabase: .none)
        enum Interrupted: Error { case checkpoint }
        do {
            let container = try ModelContainer(for: schema, configurations: [configuration])
            let context = container.mainContext
            let feedID = UUID()
            for number in 0..<2 {
                context.insert(Article(feedID: feedID, feedTitle: "Feed", externalID: "\(number)", url: "", title: "Visible \(number)", searchableText: "old noopener"))
            }
            context.insert(ArticleState(articleExternalID: "0", feedID: feedID, isRead: true, isStarred: true))
            try context.save()
            let maintenance = ArticleSearchIndexMaintenance(container: container, checkpoint: { _ in throw Interrupted.checkpoint })
            maintenance.start()
            await #expect(throws: Interrupted.self) { try await maintenance.waitUntilReady() }
        }
        let reopened = try ModelContainer(for: schema, configurations: [configuration])
        let before = try reopened.mainContext.fetch(FetchDescriptor<Article>())
        #expect(before.filter { $0.searchableText.hasPrefix(ArticleSearchableTextPolicy.formatPrefix) }.count == 1)
        let resumed = ArticleSearchIndexMaintenance(container: reopened)
        resumed.start()
        try await resumed.waitUntilReady()
        let after = try reopened.mainContext.fetch(FetchDescriptor<Article>())
        #expect(after.count == 2 && after.allSatisfy { !$0.searchableText.contains("noopener") })
        let state = try #require(reopened.mainContext.fetch(FetchDescriptor<ArticleState>()).first)
        #expect(state.isRead && state.isStarred)
    }

    @Test
    func maintenanceSaveFailureIsRetriableAndDoesNotStampAnUnsavedIndex() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let context = harness.modelContainer.mainContext
        let article = Article(feedID: UUID(), feedTitle: "Feed", externalID: "old", url: "", title: "Title", searchableText: "old")
        context.insert(article)
        try context.save()
        enum SaveFailure: Error { case failed }
        let failing = ArticleSearchIndexMaintenance(container: harness.modelContainer, save: { _ in throw SaveFailure.failed })
        failing.start()
        await #expect(throws: SaveFailure.self) { try await failing.waitUntilReady() }
        #expect(article.searchableText == "old")
        let retry = ArticleSearchIndexMaintenance(container: harness.modelContainer)
        retry.start()
        try await retry.waitUntilReady()
        #expect(article.searchableText.hasPrefix(ArticleSearchableTextPolicy.formatPrefix))
    }
}
