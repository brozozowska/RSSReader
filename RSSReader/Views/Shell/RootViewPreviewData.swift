import SwiftUI
import SwiftData

#Preview("Root Flow · Sources") {
    RootViewPreviewContainer()
}

private struct RootViewPreviewContainer: View {
    let dependencies: AppDependencies
    @State private var appState: AppState

    init() {
        let dependencies = RootViewPreviewFactory.makeDependencies()
        self.dependencies = dependencies
        self._appState = State(initialValue: RootViewPreviewFactory.makeAppState())
    }

    var body: some View {
        RootView()
            .environment(\.appDependencies, dependencies)
            .environment(\.horizontalSizeClass, .compact)
            .environment(appState)
            .applyPreviewModelContainer(dependencies.modelContainer)
    }
}

private enum RootViewPreviewFactory {
    enum SampleIDs {
        static let techFolderID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!
        static let researchFolderID = UUID(uuidString: "00000000-0000-0000-0000-000000000002")!
        static let vergeFeedID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        static let macstoriesFeedID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        static let sixcolorsFeedID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
        static let firstArticleID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        static let secondArticleID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        static let thirdArticleID = UUID(uuidString: "00000000-0000-0000-0000-000000000203")!
        static let fourthArticleID = UUID(uuidString: "00000000-0000-0000-0000-000000000204")!
    }

    @MainActor
    static func makeDependencies() -> AppDependencies {
        let schema = AppComposition.persistenceModelPartition.schema
        let configurationPlan = AppPersistenceConfigurationPlan.make(
            modelPartition: AppComposition.persistenceModelPartition,
            isStoredInMemoryOnly: true
        )
        let container = try! ModelContainer(
            for: schema,
            configurations: configurationPlan.modelContainerConfigurations
        )
        seed(container.mainContext)

        return AppDependencies(
            logger: ConsoleLogger(),
            feedFetcher: RootViewPreviewFeedFetcher(),
            modelContainer: container
        )
    }

    @MainActor
    static func makeAppState() -> AppState {
        AppState()
    }

    @MainActor
    private static func seed(_ modelContext: ModelContext) {
        let techFolder = Folder(
            id: SampleIDs.techFolderID,
            name: "Tech",
            sortOrder: 0
        )
        let researchFolder = Folder(
            id: SampleIDs.researchFolderID,
            name: "Research",
            sortOrder: 1
        )
        let verge = Feed(
            id: SampleIDs.vergeFeedID,
            url: "https://www.theverge.com/rss/index.xml",
            siteURL: "https://www.theverge.com",
            title: "The Verge"
        )
        let macstories = Feed(
            id: SampleIDs.macstoriesFeedID,
            url: "https://www.macstories.net/feed/",
            siteURL: "https://www.macstories.net",
            title: "MacStories",
            folder: techFolder
        )
        let sixcolors = Feed(
            id: SampleIDs.sixcolorsFeedID,
            url: "https://sixcolors.com/feed/",
            siteURL: "https://sixcolors.com",
            title: "Six Colors",
            folder: researchFolder
        )

        modelContext.insert(techFolder)
        modelContext.insert(researchFolder)
        modelContext.insert(verge)
        modelContext.insert(macstories)
        modelContext.insert(sixcolors)

        insertArticle(
            id: SampleIDs.firstArticleID,
            externalID: "verge-preview-1",
            title: "Apple updates Safari reading features for in-app web flows",
            summary: "Use this seeded article to move from the source list into articles and the article reader.",
            contentHTML: """
            <p>This preview article includes an inline link to <a href="https://developer.apple.com/documentation/swiftui">SwiftUI documentation</a> so the root flow can exercise the in-app web transition.</p>
            <p>The same root fixture also includes folders and grouped sources, so Source Management actions can be reached from the sidebar without switching previews.</p>
            """,
            url: "https://example.com/articles/verge-preview-1",
            publishedAt: .now,
            feed: verge,
            modelContext: modelContext
        )
        insertArticle(
            id: SampleIDs.secondArticleID,
            externalID: "verge-preview-2",
            title: "The root preview keeps one ungrouped feed for add and edit checks",
            summary: "The ungrouped source makes it easy to test edit, unsubscribe, and move-source flows.",
            url: "https://example.com/articles/verge-preview-2",
            publishedAt: .now.addingTimeInterval(-3_600),
            feed: verge,
            modelContext: modelContext
        )
        insertArticle(
            id: SampleIDs.thirdArticleID,
            externalID: "macstories-preview-1",
            title: "Grouped sources make folder actions visible in one root preview",
            summary: "This article belongs to the Tech folder fixture.",
            url: "https://example.com/articles/macstories-preview-1",
            publishedAt: .now.addingTimeInterval(-7_200),
            feed: macstories,
            modelContext: modelContext
        )
        insertArticle(
            id: SampleIDs.fourthArticleID,
            externalID: "sixcolors-preview-1",
            title: "Research folder fixture supports move and rename checks",
            summary: "This article belongs to the Research folder fixture.",
            url: "https://example.com/articles/sixcolors-preview-1",
            publishedAt: .now.addingTimeInterval(-10_800),
            feed: sixcolors,
            modelContext: modelContext
        )

        try! modelContext.save()
    }

    @MainActor
    private static func insertArticle(
        id: UUID,
        externalID: String,
        title: String,
        summary: String,
        contentHTML: String? = nil,
        url: String,
        publishedAt: Date,
        feed: Feed,
        modelContext: ModelContext
    ) {
        modelContext.insert(
            Article(
                id: id,
                feed: feed,
                externalID: externalID,
                url: url,
                canonicalURL: url,
                title: title,
                summary: summary,
                contentHTML: contentHTML,
                author: feed.title,
                publishedAt: publishedAt
            )
        )
    }
}

private struct RootViewPreviewFeedFetcher: FeedFetching {
    func fetch(_ request: FeedRequest) async throws -> FeedFetchResult {
        let siteURL = request.url.deletingLastPathComponent()
        let hostTitle = request.url.host?
            .split(separator: ".")
            .dropFirst(request.url.host?.hasPrefix("www.") == true ? 1 : 0)
            .first
            .map { $0.capitalized } ?? "Preview"
        let xml = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>\(hostTitle) Preview Feed</title>
            <link>\(siteURL.absoluteString)</link>
            <description>Preview feed generated for RootView fixtures.</description>
            <language>en</language>
            <item>
              <title>\(hostTitle) Preview Article</title>
              <link>\(siteURL.absoluteString)/articles/preview</link>
              <guid isPermaLink="false">\(request.url.absoluteString)</guid>
              <description>Preview article used by RootView preview fixtures.</description>
              <pubDate>Tue, 02 Jan 2024 10:00:00 GMT</pubDate>
            </item>
          </channel>
        </rss>
        """

        return .fetched(
            FeedResponse(
                request: request,
                sourceURL: request.url,
                statusCode: 200,
                headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                body: Data(xml.utf8)
            )
        )
    }
}

private extension View {
    @ViewBuilder
    func applyPreviewModelContainer(_ modelContainer: ModelContainer?) -> some View {
        if let modelContainer {
            self.modelContainer(modelContainer)
        } else {
            self
        }
    }
}
