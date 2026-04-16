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
        static let vergeFeedID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        static let firstArticleID = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        static let secondArticleID = UUID(uuidString: "00000000-0000-0000-0000-000000000202")!
        static let thirdArticleID = UUID(uuidString: "00000000-0000-0000-0000-000000000203")!
    }

    @MainActor
    static func makeDependencies() -> AppDependencies {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema(AppComposition.appModels)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        seed(container.mainContext)

        return AppDependencies(
            logger: ConsoleLogger(),
            feedFetcher: RootViewPreviewFeedFetcher(),
            modelContainer: container
        )
    }

    @MainActor
    static func makeAppState() -> AppState {
        let appState = AppState()
        reset(appState)
        return appState
    }

    @MainActor
    static func reset(_ appState: AppState) {
        appState.selectReadingSource(nil)
    }

    @MainActor
    private static func seed(_ modelContext: ModelContext) {
        let verge = Feed(
            id: SampleIDs.vergeFeedID,
            url: "https://www.theverge.com/rss/index.xml",
            siteURL: "https://www.theverge.com",
            title: "The Verge"
        )
        modelContext.insert(verge)

        insertArticle(
            id: SampleIDs.firstArticleID,
            externalID: "verge-preview-1",
            title: "Apple updates Safari reading features for in-app web flows",
            summary: "A preview article used to move from the single source screen into the articles list.",
            url: "https://example.com/articles/verge-preview-1",
            publishedAt: .now,
            feed: verge,
            modelContext: modelContext
        )
        insertArticle(
            id: SampleIDs.secondArticleID,
            externalID: "verge-preview-2",
            title: "The Verge preview keeps the compact root flow focused on one source",
            summary: "A second article keeps the destination list realistic once the source is selected.",
            url: "https://example.com/articles/verge-preview-2",
            publishedAt: .now.addingTimeInterval(-3600),
            feed: verge,
            modelContext: modelContext
        )
        insertArticle(
            id: SampleIDs.thirdArticleID,
            externalID: "verge-preview-3",
            title: "Three seeded articles are enough for the next preview step",
            summary: "This third article exists only to support the next shell preview stage without touching deeper navigation yet.",
            url: "https://example.com/articles/verge-preview-3",
            publishedAt: .now.addingTimeInterval(-7200),
            feed: verge,
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
                author: "The Verge",
                publishedAt: publishedAt
            )
        )
    }
}

private struct RootViewPreviewFeedFetcher: FeedFetching {
    func fetch(_ request: FeedRequest) async throws -> FeedFetchResult {
        .notModified(
            FeedResponse(
                request: request,
                sourceURL: request.url,
                statusCode: 304,
                headers: [:],
                body: Data()
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
