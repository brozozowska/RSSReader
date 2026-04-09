import SwiftUI
import SwiftData
import UIKit

struct SidebarView: View {
    @Environment(\.appDependencies) private var dependencies
    @Binding var selection: SidebarSelection?
    private let previewOverridePhase: SidebarContentPhase?
    @State private var feeds: [FeedSidebarItem] = []
    @State private var unreadSmartCount = 0
    @State private var starredSmartCount = 0
    @State private var phase: SidebarContentPhase = .loading
    @State private var expandedFolderNames = Set<String>()
    @State private var loadRequestID = UUID()

    init(
        selection: Binding<SidebarSelection?>,
        previewOverridePhase: SidebarContentPhase? = nil
    ) {
        _selection = selection
        self.previewOverridePhase = previewOverridePhase
    }

    var body: some View {
        List(selection: $selection) {
            if visibleSmartItems.isEmpty == false {
                Section {
                    ForEach(visibleSmartItems) { item in
                        smartRow(for: item)
                    }
                } header: {
                    sectionHeader("Smart Views")
                }
            }

            if folderGroups.isEmpty == false {
                Section {
                    ForEach(visibleFolderRows) { row in
                        folderSectionRow(row)
                    }
                } header: {
                    sectionHeader("Folders")
                }
            }

            if ungroupedFeeds.isEmpty == false {
                Section {
                    ForEach(ungroupedFeeds) { feed in
                        feedRow(feed)
                    }
                } header: {
                    sectionHeader("Ungrouped")
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color.white)
        .scrollDisabled(shouldDisableScrolling)
        .navigationTitle("Sources")
        .toolbarTitleDisplayMode(.inlineLarge)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    dependencies.logger.info("Add source action is not implemented yet")
                } label: {
                    Image(systemName: "plus")
                }

                Menu {
                    Button("Import") {
                        dependencies.logger.info("Import action is not implemented yet")
                    }
                    Button("Export") {
                        dependencies.logger.info("Export action is not implemented yet")
                    }
                    Button("Settings") {
                        dependencies.logger.info("Settings action is not implemented yet")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
                .accessibilityLabel("Sidebar Menu")
            }
        }
        .overlay {
            overlayContent
        }
        .task(id: loadRequestID) {
            guard previewOverridePhase == nil else { return }
            await loadFeeds()
        }
    }

    @MainActor
    private func loadFeeds() async {
        phase = .loading
        unreadSmartCount = 0
        starredSmartCount = 0

        guard let feedRepository = dependencies.feedRepository else {
            feeds = []
            phase = .failed("Sources are unavailable in the current app environment.")
            return
        }

        do {
            feeds = try feedRepository.fetchSidebarItems()
        } catch {
            dependencies.logger.error("Failed to load sidebar feeds: \(error)")
            feeds = []
            phase = .failed("Unable to load sources right now. Try again.")
            return
        }

        if let articleStateRepository = dependencies.articleStateRepository {
            do {
                let unreadCounts = try articleStateRepository.fetchUnreadCounts(feedIDs: feeds.map(\.id))
                feeds = feeds.map { feed in
                    feed.withUnreadCount(unreadCounts[feed.id, default: 0])
                }
            } catch {
                dependencies.logger.error("Failed to load unread counts for sidebar feeds: \(error)")
            }
        }

        expandedFolderNames = Set(folderGroups.map(\.name))

        if let articleQueryService = dependencies.articleQueryService {
            do {
                unreadSmartCount = try articleQueryService.fetchInboxListItems(
                    sortMode: .publishedAtDescending,
                    filter: .unread
                ).count
                starredSmartCount = try articleQueryService.fetchInboxListItems(
                    sortMode: .publishedAtDescending,
                    filter: .starred
                ).count
            } catch {
                dependencies.logger.error("Failed to load smart section counts for sidebar: \(error)")
                unreadSmartCount = 0
                starredSmartCount = 0
            }
        } else {
            unreadSmartCount = 0
            starredSmartCount = 0
        }

        if let selection {
            switch selection {
            case .inbox:
                break
            case .unread, .starred:
                break
            case .feed(let feedID):
                if feeds.contains(where: { $0.id == feedID }) == false {
                    self.selection = .inbox
                }
            }
        }

        phase = feeds.isEmpty ? .empty : .loaded
    }

    private var folderGroups: [FolderSidebarGroup] {
        let groupedFeeds = Dictionary(
            grouping: feeds.filter { $0.folderName != nil },
            by: { $0.folderName ?? "" }
        )

        let groups = groupedFeeds.map { name, feeds in
            FolderSidebarGroup(
                name: name,
                feeds: feeds.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            )
        }

        return groups.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var ungroupedFeeds: [FeedSidebarItem] {
        feeds
            .filter { $0.folderName == nil }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    private var visibleSmartItems: [SmartSidebarItem] {
        guard feeds.isEmpty == false else { return [] }

        return SmartSidebarItem.allCases.filter { item in
            switch item {
            case .allItems:
                true
            case .unread:
                unreadSmartCount > 0
            case .starred:
                starredSmartCount > 0
            }
        }
    }

    private var visibleFolderRows: [FolderSectionRow] {
        folderGroups.flatMap { group in
            var rows: [FolderSectionRow] = [.folder(group)]
            if expandedFolderNames.contains(group.name) {
                rows.append(contentsOf: group.feeds.map(FolderSectionRow.feed))
            }
            return rows
        }
    }

    private var shouldDisableScrolling: Bool {
        switch effectivePhase {
        case .loaded:
            false
        case .loading, .empty, .failed:
            true
        }
    }

    @ViewBuilder
    private var overlayContent: some View {
        switch effectivePhase {
        case .loaded:
            EmptyView()
        case .loading:
            loadingOverlay
        case .empty:
            ContentUnavailableView(
                "No Sources",
                systemImage: "dot.radiowaves.left.and.right",
                description: Text("Add a source to populate the Sources sidebar.")
            )
        case .failed(let message):
            ContentUnavailableView {
                Label("Unable to Load Sources", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Retry") {
                    retryLoad()
                }
            }
        }
    }

    private var effectivePhase: SidebarContentPhase {
        previewOverridePhase ?? phase
    }

    private var loadingOverlay: some View {
        VStack(spacing: 12) {
            ProgressView()
                .controlSize(.regular)

            Text("Loading Sources")
                .font(.headline)

            Text("Fetching feeds and counts for the sidebar.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func retryLoad() {
        loadRequestID = UUID()
    }

    @ViewBuilder
    private func smartRow(for item: SmartSidebarItem) -> some View {
        SidebarRow(
            title: item.title,
            iconSystemName: item.iconSystemName,
            count: smartCount(for: item)
        )
        .tag(Optional(item.selection))
    }

    @ViewBuilder
    private func feedRow(_ feed: FeedSidebarItem, indented: Bool = false) -> some View {
        HStack(spacing: 12) {
            SourceIconView(iconURL: feed.iconURL)

            Text(feed.title)
                .lineLimit(1)

            Spacer()

            if feed.unreadCount > 0 {
                countLabel(feed.unreadCount)
            }
        }
        .font(.body)
        .padding(.leading, indented ? 24 : 0)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .tag(Optional(SidebarSelection.feed(feed.id)))
    }

    @ViewBuilder
    private func folderRow(_ group: FolderSidebarGroup) -> some View {
        HStack(spacing: 12) {
            Button {
                toggleFolderExpansion(named: group.name)
            } label: {
                Image(systemName: expandedFolderNames.contains(group.name) ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)

            Button {
                handleFolderSelection(group)
            } label: {
                Text(group.name)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Spacer()
            if group.unreadCount > 0 {
                countLabel(group.unreadCount)
            }
        }
        .font(.body)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }

    @ViewBuilder
    private func folderSectionRow(_ row: FolderSectionRow) -> some View {
        switch row {
        case .folder(let group):
            folderRow(group)
        case .feed(let feed):
            feedRow(feed, indented: true)
        }
    }

    @ViewBuilder
    private func sectionHeader(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
    }

    @ViewBuilder
    private func countLabel(_ count: Int) -> some View {
        Text(count, format: .number)
            .font(.callout)
            .foregroundStyle(.secondary)
    }

    private func smartCount(for item: SmartSidebarItem) -> Int? {
        switch item {
        case .allItems:
            nil
        case .unread:
            unreadSmartCount
        case .starred:
            starredSmartCount
        }
    }

    private func toggleFolderExpansion(named folderName: String) {
        if expandedFolderNames.contains(folderName) {
            expandedFolderNames.remove(folderName)
        } else {
            expandedFolderNames.insert(folderName)
        }
    }

    private func handleFolderSelection(_ group: FolderSidebarGroup) {
        dependencies.logger.info(
            "Folder selection tapped for \(group.name). Folder article list navigation is not implemented yet."
        )
    }
}

enum SidebarContentPhase: Equatable {
    case loading
    case loaded
    case empty
    case failed(String)
}

#Preview("Empty Sources") {
    SidebarPreviewHost(
        dependencies: SidebarPreviewFactory.makeDependencies(for: .empty),
        selection: .inbox
    )
}

#Preview("Loading Sources") {
    SidebarPreviewHost(
        dependencies: SidebarPreviewFactory.makeDependencies(for: .empty),
        selection: .inbox,
        previewOverridePhase: .loading
    )
}

#Preview("Error Sources") {
    SidebarPreviewHost(
        dependencies: SidebarPreviewFactory.makeDependencies(for: .empty),
        selection: .inbox,
        previewOverridePhase: .failed("Unable to load sources right now. Try again.")
    )
}

#Preview("Two Sources") {
    SidebarPreviewHost(
        dependencies: SidebarPreviewFactory.makeDependencies(for: .twoSources),
        selection: .unread
    )
}

#Preview("Folders And Ungrouped") {
    SidebarPreviewHost(
        dependencies: SidebarPreviewFactory.makeDependencies(for: .foldersAndUngrouped),
        selection: .feed(SidebarPreviewFactory.SampleIDs.vergeFeedID)
    )
}

private enum SmartSidebarItem: CaseIterable, Identifiable {
    case allItems
    case unread
    case starred

    var id: String { title }

    var title: String {
        switch self {
        case .allItems:
            "All Items"
        case .unread:
            "Unread"
        case .starred:
            "Starred"
        }
    }

    var iconSystemName: String {
        switch self {
        case .allItems:
            "tray.full"
        case .unread:
            "circle"
        case .starred:
            "star"
        }
    }

    var selection: SidebarSelection {
        switch self {
        case .allItems:
            .inbox
        case .unread:
            .unread
        case .starred:
            .starred
        }
    }
}

private struct FolderSidebarGroup: Identifiable {
    let name: String
    let feeds: [FeedSidebarItem]

    var id: String { name }
    var unreadCount: Int { feeds.reduce(0) { $0 + $1.unreadCount } }
}

private enum FolderSectionRow: Identifiable {
    case folder(FolderSidebarGroup)
    case feed(FeedSidebarItem)

    var id: String {
        switch self {
        case .folder(let group):
            "folder-\(group.id)"
        case .feed(let feed):
            "feed-\(feed.id.uuidString)"
        }
    }
}

private struct SidebarRow: View {
    let title: String
    let iconSystemName: String
    let count: Int?
    let leadingPadding: CGFloat

    init(
        title: String,
        iconSystemName: String,
        count: Int?,
        leadingPadding: CGFloat = 0
    ) {
        self.title = title
        self.iconSystemName = iconSystemName
        self.count = count
        self.leadingPadding = leadingPadding
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconSystemName)
                .font(.body.weight(.medium))
                .frame(width: 20)
                .foregroundStyle(.primary)

            Text(title)
                .lineLimit(1)

            Spacer()

            if let count, count > 0 {
                Text(count, format: .number)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .font(.body)
        .padding(.leading, leadingPadding)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

private struct SourceIconView: View {
    @Environment(\.appDependencies) private var dependencies
    let iconURL: String?
    @State private var iconImage: Image?
    @State private var loadTask: Task<Void, Never>?

    var body: some View {
        Group {
            if let iconImage {
                iconImage
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .task(id: iconURL) {
            await loadIcon()
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private var resolvedURL: URL? {
        guard let iconURL else { return nil }
        return URL(string: iconURL)
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(Color.secondary.opacity(0.12))

            Image(systemName: "newspaper")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
        }
    }

    @MainActor
    private func loadIcon() async {
        loadTask?.cancel()
        iconImage = nil

        guard let resolvedURL else {
            return
        }

        let task = Task {
            do {
                let data = try await dependencies.sourceIconCache.imageData(for: resolvedURL)
                try Task.checkCancellation()

                guard let uiImage = UIImage(data: data) else {
                    return
                }

                await MainActor.run {
                    iconImage = Image(uiImage: uiImage)
                }
            } catch is CancellationError {
                return
            } catch {
                dependencies.logger.debug(
                    "Failed to load source icon for \(resolvedURL.absoluteString): \(String(describing: error))"
                )
            }
        }

        loadTask = task
        await task.value
    }
}

private struct SidebarPreviewHost: View {
    let dependencies: AppDependencies
    let previewOverridePhase: SidebarContentPhase?
    @State var selection: SidebarSelection?

    init(
        dependencies: AppDependencies,
        selection: SidebarSelection?,
        previewOverridePhase: SidebarContentPhase? = nil
    ) {
        self.dependencies = dependencies
        self.previewOverridePhase = previewOverridePhase
        _selection = State(initialValue: selection)
    }

    var body: some View {
        NavigationStack {
            SidebarView(
                selection: $selection,
                previewOverridePhase: previewOverridePhase
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
