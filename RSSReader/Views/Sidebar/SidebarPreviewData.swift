import SwiftUI
import SwiftData

#Preview("Loading Sources") {
    SidebarPreviewHost(
        scenario: .empty,
        selection: .inbox,
        previewPhase: .loading
    )
}

#Preview("Empty Sources") {
    SidebarPreviewHost(
        scenario: .empty,
        selection: .inbox
    )
}

#Preview("Error Sources") {
    SidebarPreviewHost(
        scenario: .empty,
        selection: .inbox,
        previewPhase: .failed("Unable to load sources right now. Try again.")
    )
}

#Preview("Two Sources") {
    SidebarPreviewHost(
        scenario: .twoSources,
        selection: .unread
    )
}

#Preview("Folders And Ungrouped") {
    SidebarPreviewHost(
        scenario: .foldersAndUngrouped,
        selection: .feed(SidebarPreviewFactory.SampleIDs.vergeFeedID)
    )
}

private struct SidebarPreviewHost: View {
    let dependencies: AppDependencies
    let previewScreenState: SidebarScreenState
    @State var selection: SidebarSelection?

    init(
        scenario: SidebarPreviewScenario,
        selection: SidebarSelection?,
        previewPhase: SidebarContentPhase? = nil
    ) {
        let dependencies = SidebarPreviewFactory.makeDependencies(for: scenario)
        self.dependencies = dependencies
        self.previewScreenState = SidebarPreviewFactory.makeScreenState(
            dependencies: dependencies,
            previewPhase: previewPhase
        )
        _selection = State(initialValue: selection)
    }

    var body: some View {
        NavigationStack {
            SidebarView(
                selection: $selection,
                previewScreenState: previewScreenState
            )
        }
        .environment(\.appDependencies, dependencies)
        .environment(AppState())
        .applyPreviewModelContainer(dependencies.modelContainer)
    }
}

private enum SidebarPreviewScenario {
    case empty
    case twoSources
    case foldersAndUngrouped
}

private enum SidebarPreviewFactory {
    enum SampleIDs {
        static let vergeFeedID = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
        static let macmostFeedID = UUID(uuidString: "00000000-0000-0000-0000-000000000102")!
        static let redditFeedID = UUID(uuidString: "00000000-0000-0000-0000-000000000103")!
        static let bloombergFeedID = UUID(uuidString: "00000000-0000-0000-0000-000000000104")!
    }

    @MainActor
    static func makeDependencies(for scenario: SidebarPreviewScenario) -> AppDependencies {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        let schema = Schema(AppComposition.appModels)
        let container = try! ModelContainer(for: schema, configurations: [configuration])
        seed(container.mainContext, for: scenario)
        return AppDependencies(
            logger: ConsoleLogger(),
            modelContainer: container
        )
    }

    @MainActor
    static func makeScreenState(
        dependencies: AppDependencies,
        previewPhase: SidebarContentPhase?
    ) -> SidebarScreenState {
        if let previewPhase {
            switch previewPhase {
            case .loading:
                return .previewLoading()
            case .failed(let message):
                return .previewFailed(message: message)
            case .loaded, .empty:
                break
            }
        }

        guard let sourcesSidebarQueryService = dependencies.sourcesSidebarQueryService else {
            return .previewFailed(message: "Sources are unavailable in the current app environment.")
        }

        let snapshot = (try? sourcesSidebarQueryService.fetchSnapshot()) ?? SourcesSidebarSnapshotDTO(
            feeds: [],
            unreadSmartCount: 0,
            starredSmartCount: 0,
            starredFeedIDs: []
        )

        return .previewLoaded(snapshot: snapshot)
    }

    @MainActor
    private static func seed(_ modelContext: ModelContext, for scenario: SidebarPreviewScenario) {
        switch scenario {
        case .empty:
            break
        case .twoSources:
            seedTwoSources(into: modelContext)
        case .foldersAndUngrouped:
            seedFoldersAndUngrouped(into: modelContext)
        }

        try! modelContext.save()
    }

    @MainActor
    private static func seedTwoSources(into modelContext: ModelContext) {
        let verge = Feed(
            id: SampleIDs.vergeFeedID,
            url: "https://www.theverge.com/rss/index.xml",
            title: "The Verge"
        )
        let macMost = Feed(
            id: SampleIDs.macmostFeedID,
            url: "https://macmost.com/rss",
            title: "MacMost"
        )

        modelContext.insert(verge)
        modelContext.insert(macMost)

        insertArticle(
            feed: verge,
            externalID: "verge-1",
            title: "Unread story",
            modelContext: modelContext
        )
        insertArticle(
            feed: verge,
            externalID: "verge-2",
            title: "Starred story",
            modelContext: modelContext,
            isStarred: true
        )
        insertArticle(
            feed: macMost,
            externalID: "macmost-1",
            title: "Read story",
            modelContext: modelContext,
            isRead: true
        )
    }

    @MainActor
    private static func seedFoldersAndUngrouped(into modelContext: ModelContext) {
        let news = Folder(name: "News")
        let tech = Folder(name: "Tech")

        let reddit = Feed(
            id: SampleIDs.redditFeedID,
            url: "https://reddit.com/r/apple/.rss",
            title: "Reddit",
            folder: news
        )
        let verge = Feed(
            id: SampleIDs.vergeFeedID,
            url: "https://www.theverge.com/rss/index.xml",
            title: "The Verge",
            folder: tech
        )
        let macMost = Feed(
            id: SampleIDs.macmostFeedID,
            url: "https://macmost.com/rss",
            title: "MacMost",
            folder: tech
        )
        let bloomberg = Feed(
            id: SampleIDs.bloombergFeedID,
            url: "https://www.bloomberg.com/feed/podcast/etf-report.xml",
            title: "Bloomberg"
        )

        modelContext.insert(news)
        modelContext.insert(tech)
        modelContext.insert(reddit)
        modelContext.insert(verge)
        modelContext.insert(macMost)
        modelContext.insert(bloomberg)

        insertArticle(
            feed: reddit,
            externalID: "reddit-1",
            title: "Unread reddit story",
            modelContext: modelContext
        )
        insertArticle(
            feed: reddit,
            externalID: "reddit-2",
            title: "Read reddit story",
            modelContext: modelContext,
            isRead: true
        )
        insertArticle(
            feed: verge,
            externalID: "verge-1",
            title: "Unread verge story",
            modelContext: modelContext
        )
        insertArticle(
            feed: verge,
            externalID: "verge-2",
            title: "Starred verge story",
            modelContext: modelContext,
            isStarred: true
        )
        insertArticle(
            feed: macMost,
            externalID: "macmost-1",
            title: "Unread mac story",
            modelContext: modelContext
        )
        insertArticle(
            feed: bloomberg,
            externalID: "bloomberg-1",
            title: "Read bloomberg story",
            modelContext: modelContext,
            isRead: true
        )
    }

    @MainActor
    private static func insertArticle(
        feed: Feed,
        externalID: String,
        title: String,
        modelContext: ModelContext,
        isRead: Bool = false,
        isStarred: Bool = false
    ) {
        let article = Article(
            feed: feed,
            externalID: externalID,
            url: "https://example.com/articles/\(externalID)",
            title: title
        )

        modelContext.insert(article)

        guard isRead || isStarred else { return }

        let articleState = ArticleState(
            articleExternalID: externalID,
            feedID: feed.id,
            isRead: isRead,
            readAt: isRead ? .now : nil,
            isStarred: isStarred,
            starredAt: isStarred ? .now : nil,
            updatedAt: .now
        )
        modelContext.insert(articleState)
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
