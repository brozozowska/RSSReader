import Foundation
import Testing
@testable import RSSReader

@Suite("Queries / Article Search Scope")
@MainActor
struct ArticleSearchScopeTests {
    @Test
    func articleSearchScopeMatchesDocumentedSearchableFields() {
        let titleMatch = makeArticleSearchCandidateDTO(articleExternalID: "title", title: "Swift concurrency")
        let summaryMatch = makeArticleSearchCandidateDTO(articleExternalID: "summary", title: "Article", summary: "Architecture notes")
        let contentTextMatch = makeArticleSearchCandidateDTO(
            articleExternalID: "content-text",
            title: "Article",
            summary: nil,
            contentText: "Reader polish foundation"
        )
        let contentHTMLMatch = makeArticleSearchCandidateDTO(
            articleExternalID: "content-html",
            title: "Article",
            summary: nil,
            contentHTML: "<p>Searchable <strong>HTML fallback</strong></p>"
        )
        let authorMatch = makeArticleSearchCandidateDTO(articleExternalID: "author", title: "Article", author: "Jane Search")
        let feedTitleMatch = makeArticleSearchCandidateDTO(
            feedTitle: "Searchable Feed",
            articleExternalID: "feed-title",
            title: "Article"
        )
        let miss = makeArticleSearchCandidateDTO(articleExternalID: "miss", title: "Other")
        let articles = [titleMatch, summaryMatch, contentTextMatch, contentHTMLMatch, authorMatch, feedTitleMatch, miss]

        #expect(matchingExternalIDs(in: articles, query: "concurrency") == ["title"])
        #expect(matchingExternalIDs(in: articles, query: "architecture") == ["summary"])
        #expect(matchingExternalIDs(in: articles, query: "polish") == ["content-text"])
        #expect(matchingExternalIDs(in: articles, query: "html fallback") == ["content-html"])
        #expect(matchingExternalIDs(in: articles, query: "jane") == ["author"])
        #expect(matchingExternalIDs(in: articles, query: "searchable feed") == ["feed-title"])
    }

    @Test
    func articleSearchScopeInheritsSelectionAndSidebarFilterVisibilityContract() {
        let unread = makeArticleSearchCandidateDTO(articleExternalID: "unread", title: "Needle", isRead: false)
        let read = makeArticleSearchCandidateDTO(articleExternalID: "read", title: "Needle", isRead: true)
        let starred = makeArticleSearchCandidateDTO(articleExternalID: "starred", title: "Needle", isRead: true, isStarred: true)
        let hidden = makeArticleSearchCandidateDTO(articleExternalID: "hidden", title: "Needle", isHidden: true)
        let archived = makeArticleSearchCandidateDTO(
            articleExternalID: "archived",
            title: "Needle",
            archivedAt: Date(timeIntervalSince1970: 100)
        )
        let preScopedArticles = [unread, read, starred, hidden, archived]

        #expect(
            matchingExternalIDs(
                in: preScopedArticles,
                query: "needle",
                selection: .inbox,
                sidebarArticleFilter: .allItems
            ) == ["unread", "read", "starred", "archived"]
        )
        #expect(
            matchingExternalIDs(
                in: preScopedArticles,
                query: "needle",
                selection: .unread,
                sidebarArticleFilter: .allItems
            ) == ["unread", "archived"]
        )
        #expect(
            matchingExternalIDs(
                in: preScopedArticles,
                query: "needle",
                selection: .starred,
                sidebarArticleFilter: .allItems
            ) == ["starred"]
        )
        #expect(
            matchingExternalIDs(
                in: preScopedArticles,
                query: "needle",
                selection: .folder("Tech"),
                sidebarArticleFilter: .starred
            ) == ["starred"]
        )
    }

    @Test
    func articleSearchScopeReturnsCurrentVisibleScopeForEmptySearchText() {
        let unread = makeArticleSearchCandidateDTO(articleExternalID: "unread", title: "Unread", isRead: false)
        let read = makeArticleSearchCandidateDTO(articleExternalID: "read", title: "Read", isRead: true)
        let archived = makeArticleSearchCandidateDTO(
            articleExternalID: "archived",
            title: "Archived",
            archivedAt: Date(timeIntervalSince1970: 100)
        )

        let results = ArticleSearchScope.filteredCandidates(
            [unread, read, archived],
            searchText: " \t\n\r ",
            selection: .feed(unread.listItem.feedID),
            sidebarArticleFilter: .unread
        )

        #expect(results.map { $0.listItem.articleExternalID } == ["unread", "archived"])
    }

    @Test
    func articleSearchQueryNormalizationAlignsCanonicalAndWhitespaceForms() {
        let candidate = makeArticleSearchCandidateDTO(
            articleExternalID: "canonical-whitespace",
            title: "Café\treader\npolish"
        )
        let rawQuery = "  Cafe\u{301}   reader\t\npolish  "
        let scope = ArticleSearchScope(
            searchText: rawQuery,
            selection: .inbox,
            sidebarArticleFilter: .allItems
        )
        let request = ArticleSearchRequest(
            selection: .inbox,
            sidebarArticleFilter: .allItems,
            query: rawQuery,
            sortMode: .publishedAtDescending
        )

        #expect(scope.normalizedQuery == "Café reader polish")
        #expect(request.normalizedQuery == scope.normalizedQuery)
        #expect(scope.contains(candidate))
        #expect(matchingExternalIDs(in: [candidate], query: "Café reader polish") == ["canonical-whitespace"])
        #expect(matchingExternalIDs(in: [candidate], query: "Café   reader\tpolish") == ["canonical-whitespace"])
    }

    @Test
    func articleSearchQueryNormalizationBoundsInputAndPreservesBlankSemantics() {
        let oversizedQuery = String(
            repeating: "а",
            count: ArticleSearchQueryNormalizationPolicy.maximumUTF8ByteCount
        )
        let normalizedOversizedQuery = ArticleSearchScope.normalizedSearchText(oversizedQuery)
        let blankRequest = ArticleSearchRequest(
            selection: .inbox,
            sidebarArticleFilter: .allItems,
            query: " \t\n ",
            sortMode: .publishedAtDescending,
            emptyQueryBehavior: .returnsEmpty
        )

        #expect(
            normalizedOversizedQuery.utf8.count
                <= ArticleSearchQueryNormalizationPolicy.maximumUTF8ByteCount
        )
        #expect(normalizedOversizedQuery.isEmpty == false)
        #expect(blankRequest.normalizedQuery.isEmpty)
        #expect(blankRequest.shouldReturnEmptyForBlankQuery)
    }

    @Test
    func articleSearchScopeUsesMaterializedTextWithoutParsingRawHTML() {
        let article = makeArticleSearchCandidateDTO(
            articleExternalID: "materialized",
            title: "Article",
            summary: nil,
            contentHTML: "<p>Legacy raw token</p>",
            searchableText: "Current materialized token"
        )

        #expect(matchingExternalIDs(in: [article], query: "materialized token") == ["materialized"])
        #expect(matchingExternalIDs(in: [article], query: "legacy raw token").isEmpty)
    }

    @Test
    func articleSearchableTextPolicyNormalizesHTMLAndBoundsUTF8Output() {
        let normalized = ArticleSearchableTextPolicy.materialize(
            title: "  Search   title  ",
            summary: nil,
            contentHTML: "<p>HTML&nbsp;<strong>fallback</strong></p>",
            contentText: nil,
            author: " Jane   Search "
        )
        let bounded = ArticleSearchableTextPolicy.materialize(
            title: "Article",
            summary: nil,
            contentHTML: nil,
            contentText: String(repeating: "а", count: ArticleSearchableTextPolicy.maximumUTF8ByteCount),
            author: nil
        )

        #expect(normalized == "Search title Jane Search HTML fallback")
        #expect(bounded.utf8.count <= ArticleSearchableTextPolicy.maximumUTF8ByteCount)
        #expect(bounded.isEmpty == false)
    }

    private func matchingExternalIDs(
        in candidates: [ArticleSearchCandidateDTO],
        query: String,
        selection: SidebarSelection? = .inbox,
        sidebarArticleFilter: SidebarArticleFilter = .allItems
    ) -> [String] {
        ArticleSearchScope.filteredCandidates(
            candidates,
            searchText: query,
            selection: selection,
            sidebarArticleFilter: sidebarArticleFilter
        )
        .map { $0.listItem.articleExternalID }
    }
}
