import SwiftUI
import SwiftData
import UIKit

struct SidebarView: View {
    // MARK: Dependencies

    @Environment(\.appDependencies) private var dependencies
    @Environment(AppState.self) private var appState

    // MARK: Configuration

    @Binding var selection: SidebarSelection?
    let previewScreenState: SidebarScreenState?

    // MARK: View State

    @State private var controller: SidebarScreenController
    @State private var expandedFolderNames = Set<String>()

    init(
        selection: Binding<SidebarSelection?>,
        previewScreenState: SidebarScreenState? = nil
    ) {
        _selection = selection
        self.previewScreenState = previewScreenState
        self._controller = State(initialValue: SidebarScreenController(previewScreenState: previewScreenState))
    }

    // MARK: Body

    var body: some View {
        let viewState = controller.screenState.derivedViewState(
            filter: appState.selectedSourcesFilter,
            expandedFolderNames: expandedFolderNames
        )

        List(selection: $selection) {
            if viewState.visibleSmartItems.isEmpty == false {
                Section {
                    ForEach(viewState.visibleSmartItems) { item in
                        smartRow(for: item, smartCount: viewState.smartCount)
                    }
                } header: {
                    if viewState.visibleSmartItems.count > 1 {
                        sectionHeader("Smart Views")
                    }
                }
            }

            if viewState.visibleFolderRows.isEmpty == false {
                Section {
                    ForEach(viewState.visibleFolderRows) { row in
                        folderSectionRow(row)
                    }
                } header: {
                    sectionHeader("Folders")
                }
            }

            if viewState.ungroupedFeeds.isEmpty == false {
                Section {
                    ForEach(viewState.ungroupedFeeds) { feed in
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
        .scrollDisabled(viewState.shouldDisableScrolling)
        .refreshable {
            await refreshSources()
        }
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                sidebarActionsMenu
            }

            ToolbarItem(placement: .title) {
                titleView
            }

            ToolbarItem(placement: .subtitle) {
                subtitleView
            }

            ToolbarItemGroup(placement: .topBarTrailing) {
                addSourceButton
                sourcesFilterMenu
            }
        }
        .overlay {
            overlayContent(using: viewState)
        }
        .task {
            guard previewScreenState == nil else { return }
            await loadFeeds(showsFullScreenLoading: true, refreshedAt: .now)
        }
        .onChange(of: appState.sourcesSidebarReloadID) { _, _ in
            guard previewScreenState == nil else { return }
            Task {
                await loadFeeds(showsFullScreenLoading: false, refreshedAt: nil)
            }
        }
        .onChange(of: appState.selectedSourcesFilter) { _, _ in
            selection = controller.resolvedSelection(
                currentSelection: selection,
                filter: appState.selectedSourcesFilter
            )
        }
    }

    @ViewBuilder
    private func overlayContent(using viewState: SidebarScreenDerivedViewState) -> some View {
        if let primaryLoadingState = viewState.primaryLoadingState {
            ScreenLoadingView(title: primaryLoadingState.title)
        } else if let placeholder = viewState.placeholder {
            ScreenPlaceholderView(
                title: placeholder.title,
                systemImage: placeholder.systemImage,
                description: placeholder.description
            )
        }
    }

    private var toolbarState: SidebarToolbarState {
        controller.screenState.derivedViewState(
            filter: appState.selectedSourcesFilter,
            expandedFolderNames: expandedFolderNames
        ).toolbarState
    }

    private var isSyncing: Bool {
        controller.screenState.isSyncing
    }

    // MARK: Status And Overlay UI

    private var titleView: some View {
        Text("Sources")
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var subtitleView: some View {
        Text(toolbarState.subtitle)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: User Actions

    private var sidebarActionsMenu: some View {
        Menu {
            Button("Import") {
                // TODO: Replace with OPML import flow.
                dependencies.logger.info("Import action is not implemented yet")
            }

            Button("Export") {
                // TODO: Replace with OPML export flow.
                dependencies.logger.info("Export action is not implemented yet")
            }

            Divider()

            Button("Settings") {
                // TODO: Present settings screen when Settings Integration is implemented.
                dependencies.logger.info("Settings action is not implemented yet")
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .accessibilityLabel("Sidebar Actions")
    }

    private var addSourceButton: some View {
        Button {
            // TODO: Wire Add Source action when Source Management flow is implemented.
            dependencies.logger.info("Add source action is not implemented yet")
        } label: {
            Image(systemName: "plus")
        }
        .accessibilityLabel("Add Source")
    }

    private var sourcesFilterMenu: some View {
        Menu {
            sourcesFilterButton("All Items", filter: .allItems)
            sourcesFilterButton("Unread", filter: .unread)
            sourcesFilterButton("Starred", filter: .starred)
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .accessibilityLabel("Filter Sources")
    }

    @ViewBuilder
    private func sourcesFilterButton(_ title: String, filter: SourcesFilter) -> some View {
        Button {
            dependencies.applySourcesFilter(filter, using: appState)
        } label: {
            if appState.selectedSourcesFilter == filter {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }

    @MainActor
    private func loadFeeds(showsFullScreenLoading: Bool, refreshedAt: Date?) async {
        let adjustedSelection = await controller.loadFeeds(
            showsFullScreenLoading: showsFullScreenLoading,
            dependencies: dependencies,
            currentSelection: selection,
            filter: appState.selectedSourcesFilter,
            refreshedAt: refreshedAt
        )

        selection = adjustedSelection
        expandedFolderNames = controller.visibleFolderNames(filter: appState.selectedSourcesFilter)
    }

    @MainActor
    private func refreshSources() async {
        guard previewScreenState == nil, isSyncing == false else { return }

        let adjustedSelection = await controller.refreshSources(
            dependencies: dependencies,
            appState: appState,
            currentSelection: selection,
            filter: appState.selectedSourcesFilter
        )

        selection = adjustedSelection
        expandedFolderNames = controller.visibleFolderNames(filter: appState.selectedSourcesFilter)
    }

    @ViewBuilder
    private func smartRow(for item: SmartSidebarItem, smartCount: Int?) -> some View {
        SidebarRow(
            title: item.title,
            iconSystemName: item.iconSystemName,
            count: smartCount
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selection = item.selection
        }
        .tag(Optional(item.selection))
    }

    @ViewBuilder
    private func feedRow(_ feed: FeedSidebarItem, indented: Bool = false) -> some View {
        HStack(spacing: 12) {
            SourceIconView(iconURL: feed.iconURL)

            Text(feed.title)
                .lineLimit(1)

            Spacer()

            let count = SidebarCountPresentation.feedCount(
                for: feed,
                filter: appState.selectedSourcesFilter
            )
            if count > 0 {
                countLabel(count)
            }
        }
        .font(.body)
        .padding(.leading, indented ? 24 : 0)
        .contentShape(Rectangle())
        .onTapGesture {
            selection = .feed(feed.id)
        }
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
            let count = SidebarCountPresentation.folderCount(
                for: group,
                filter: appState.selectedSourcesFilter
            )
            if count > 0 {
                countLabel(count)
            }
        }
        .font(.body)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .tag(Optional(SidebarSelection.folder(group.name)))
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

    private func toggleFolderExpansion(named folderName: String) {
        if expandedFolderNames.contains(folderName) {
            expandedFolderNames.remove(folderName)
        } else {
            expandedFolderNames.insert(folderName)
        }
    }

    private func handleFolderSelection(_ group: FolderSidebarGroup) {
        dependencies.showFolder(named: group.name, using: appState)
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
// MARK: - Previews

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
