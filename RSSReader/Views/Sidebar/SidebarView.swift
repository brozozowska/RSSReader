import SwiftUI
import SwiftData
import UIKit

struct SidebarView: View {
    // MARK: Dependencies

    @Environment(\.appDependencies) private var dependencies
    @Environment(AppState.self) private var appState
    @Environment(\.appThemeVariant) private var appThemeVariant

    // MARK: Configuration

    @Binding var selection: SidebarSelection?

    // MARK: View State

    @State private var controller: SidebarScreenController

    init(
        selection: Binding<SidebarSelection?>,
        previewScreenState: SidebarScreenState? = nil
    ) {
        _selection = selection
        self._controller = State(initialValue: SidebarScreenController(previewScreenState: previewScreenState))
    }

    // MARK: Body

    var body: some View {
        let viewState = controller.viewState(
            filter: appState.selectedSourcesFilter,
            iCloudSyncStatus: appState.iCloudSyncStatus
        )

        ZStack {
            sidebarList(viewState)
            customRefreshIndicator
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
                subtitleView(toolbarState: viewState.toolbarState)
            }

            ToolbarItem(placement: .topBarTrailing) {
                addSourceButton
            }

            ToolbarSpacer(.fixed, placement: .topBarTrailing)

            ToolbarItem(placement: .topBarTrailing) {
                sourcesFilterMenu
            }
        }
        .overlay {
            overlayContent(using: viewState)
        }
        .task {
            guard controller.isPreviewMode == false else { return }
            await loadFeeds(showsFullScreenLoading: true, refreshedAt: nil)
        }
        .onChange(of: appState.sourcesSidebarReloadID) { _, _ in
            guard controller.isPreviewMode == false else { return }
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

    private func sidebarList(_ viewState: SidebarScreenDerivedViewState) -> some View {
        List(selection: $selection) {
            sidebarSections(viewState)
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(appThemeVariant.primaryBackground)
        .scrollDisabled(viewState.shouldDisableScrolling)
        .onScrollGeometryChange(for: SidebarCustomRefreshGeometry.self) { geometry in
            SidebarCustomRefreshGeometry(
                contentOffsetY: geometry.contentOffset.y,
                contentInsetTop: geometry.contentInsets.top
            )
        } action: { _, newGeometry in
            let progress = SidebarCustomRefreshPullPolicy.progress(for: newGeometry)
            updateCustomRefreshPullProgress(progress)
        }
        .onScrollPhaseChange { oldPhase, newPhase, _ in
            guard SidebarCustomRefreshReleasePolicy.shouldTriggerRefresh(
                wasInteracting: oldPhase == .interacting,
                isInteracting: newPhase == .interacting,
                customRefreshState: controller.screenState.customRefreshState
            ) else {
                return
            }

            Task {
                await triggerCustomRefresh()
            }
        }
    }

    @ViewBuilder
    private func sidebarSections(_ viewState: SidebarScreenDerivedViewState) -> some View {
        if viewState.smartRows.isEmpty == false {
            Section {
                ForEach(viewState.smartRows) { row in
                    smartRow(row)
                }
            } header: {
                if viewState.smartRows.count > 1 {
                    sectionHeader("Smart Views")
                }
            }
        }

        if viewState.folderRows.isEmpty == false {
            Section {
                ForEach(viewState.folderRows) { row in
                    folderSectionRow(row)
                }
            } header: {
                sectionHeader("Folders")
            }
        }

        if viewState.ungroupedFeedRows.isEmpty == false {
            Section {
                ForEach(viewState.ungroupedFeedRows) { feed in
                    feedRow(feed)
                }
            } header: {
                sectionHeader("Ungrouped")
            }
        }
    }

    @ViewBuilder
    private var customRefreshIndicator: some View {
        if controller.screenState.customRefreshState.showsIndicator {
            VStack {
                AppRefreshIndicator(
                    state: controller.screenState.customRefreshState.indicatorState,
                    size: 24,
                    lineWidth: 2.5
                )
                .padding(.top, 14)

                Spacer()
            }
            .allowsHitTesting(false)
            .transition(.opacity)
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

    // MARK: Status And Overlay UI

    private var titleView: some View {
        Text("Sources")
            .font(.title3.weight(.semibold))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func subtitleView(toolbarState: SidebarToolbarState) -> some View {
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
                dependencies.showSettings(using: appState)
            }
        } label: {
            Image(systemName: "gearshape")
        }
        .accessibilityLabel("Sidebar Actions")
    }

    private var addSourceButton: some View {
        Button {
            dependencies.showSourceManagement(using: appState)
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
    }

    @MainActor
    private func refreshSources() async {
        guard controller.isPreviewMode == false, controller.screenState.isSyncing == false else { return }

        let adjustedSelection = await controller.refreshSources(
            dependencies: dependencies,
            appState: appState,
            currentSelection: selection,
            filter: appState.selectedSourcesFilter
        )

        selection = adjustedSelection
    }

    @MainActor
    private func updateCustomRefreshPullProgress(_ progress: Double) {
        controller.screenState.updateCustomRefreshPullProgress(progress)
    }

    @MainActor
    private func triggerCustomRefresh() async {
        guard controller.isPreviewMode == false else { return }
        guard controller.screenState.customRefreshState.phase == .ready else { return }

        controller.screenState.beginCustomRefresh()
        defer {
            controller.screenState.endCustomRefresh()
        }

        await refreshSources()
    }

    private func smartRow(_ row: SidebarSmartRowState) -> some View {
        SidebarRow(
            title: row.title,
            iconSystemName: row.iconSystemName,
            count: row.count
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selection = row.selection
        }
        .tag(Optional(row.selection))
    }

    private func feedRow(_ row: SidebarFeedRowState) -> some View {
        HStack(spacing: 12) {
            SourceIconView(siteURL: row.siteURL, iconURL: row.iconURL)

            Text(row.title)
                .lineLimit(1)

            Spacer()

            if row.count > 0 {
                countLabel(row.count)
            }
        }
        .font(.body)
        .padding(.leading, row.isIndented ? 24 : 0)
        .contentShape(Rectangle())
        .onTapGesture {
            selection = row.selection
        }
        .contextMenu {
            Button("Organize...") {
                dependencies.showFeedOrganizer(id: row.id, using: appState)
            }

            Button("Edit...") {
                dependencies.showFeedEditor(id: row.id, using: appState)
            }

            Button("Unsubscribe", role: .destructive) {
                dependencies.unsubscribeFeed(id: row.id, using: appState)
            }
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .tag(Optional(row.selection))
    }

    private func folderRow(_ row: SidebarFolderRowState) -> some View {
        HStack(spacing: 12) {
            Button {
                controller.toggleFolderExpansion(named: row.name)
            } label: {
                Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)

            Button {
                dependencies.showFolder(named: row.name, using: appState)
                selection = row.selection
            } label: {
                Text(row.name)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Spacer()
            if row.count > 0 {
                countLabel(row.count)
            }
        }
        .font(.body)
        .contextMenu {
            Button("Edit...") {
                dependencies.showFolderEditor(named: row.name, using: appState)
            }

            Button("Delete", role: .destructive) {
                dependencies.deleteFolder(named: row.name, using: appState)
            }
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .tag(Optional(row.selection))
    }

    @ViewBuilder
    private func folderSectionRow(_ row: SidebarFolderSectionRowState) -> some View {
        switch row {
        case .folder(let row):
            folderRow(row)
        case .feed(let feed):
            feedRow(feed)
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
    @Environment(AppState.self) private var appState
    let siteURL: String?
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
        .task(id: cacheOnlyLoadID) {
            await loadIcon(allowsNetworkDiscovery: false)
        }
        .onChange(of: appState.sourceIconReloadID) { _, _ in
            Task {
                await loadIcon(allowsNetworkDiscovery: true)
            }
        }
        .onChange(of: appState.sourceIconCacheResetID) { _, _ in
            loadTask?.cancel()
            loadTask = nil
            iconImage = nil
        }
        .onDisappear {
            loadTask?.cancel()
            loadTask = nil
        }
    }

    private var cacheOnlyLoadID: SourceIconCacheOnlyLoadID {
        SourceIconCacheOnlyLoadID(
            siteURL: siteURL,
            iconURL: iconURL,
            sidebarReloadID: appState.sourcesSidebarReloadID
        )
    }

    private var resolvedURL: URL? {
        guard let iconURL else { return nil }
        return URL(string: iconURL)
    }

    private var resolvedSiteURL: URL? {
        guard let siteURL else { return nil }
        return URL(string: siteURL)
    }

    private var placeholder: some View {
        Image(systemName: "newspaper")
            .font(.body.weight(.medium))
            .foregroundStyle(.secondary)
    }

    @MainActor
    private func loadIcon(allowsNetworkDiscovery: Bool) async {
        loadTask?.cancel()
        iconImage = nil

        guard let resolvedURL else {
            return
        }

        let task = Task {
            if await loadFirstAvailableIcon(
                from: [resolvedURL],
                allowsNetworkDiscovery: allowsNetworkDiscovery,
                cacheAliasURL: nil
            ) {
                return
            }

            let fallbackOriginURL = resolvedSiteURL
                .flatMap(SourceIconCandidateBuilder.originURL(for:))
                ?? SourceIconCandidateBuilder.originURL(for: resolvedURL)

            if allowsNetworkDiscovery,
               let originURL = fallbackOriginURL,
               let html = await fetchSourceHomeHTML(from: originURL),
               await loadFirstAvailableIcon(
                from: SourceIconCandidateBuilder.htmlIconCandidates(in: html, baseURL: originURL),
                allowsNetworkDiscovery: true,
                cacheAliasURL: resolvedURL
               ) {
                return
            }

            _ = await loadFirstAvailableIcon(
                from: SourceIconCandidateBuilder.commonIconCandidates(for: fallbackOriginURL ?? resolvedURL),
                allowsNetworkDiscovery: allowsNetworkDiscovery,
                cacheAliasURL: allowsNetworkDiscovery ? resolvedURL : nil
            )
        }

        loadTask = task
        await task.value
    }

    private func loadFirstAvailableIcon(
        from iconURLs: [URL],
        allowsNetworkDiscovery: Bool,
        cacheAliasURL: URL?
    ) async -> Bool {
        for iconURL in iconURLs {
            do {
                let data: Data?
                if allowsNetworkDiscovery {
                    data = try await dependencies.sourceIconCache.imageData(for: iconURL)
                } else {
                    data = try await dependencies.sourceIconCache.cachedImageData(for: iconURL)
                }
                try Task.checkCancellation()

                guard let data,
                      let uiImage = UIImage(data: data),
                      SourceIconImagePolicy.isSuitableIconSize(uiImage.size) else {
                    continue
                }

                if allowsNetworkDiscovery,
                   let cacheAliasURL,
                   cacheAliasURL != iconURL {
                    try await dependencies.sourceIconCache.storeImageData(data, for: cacheAliasURL)
                }

                await MainActor.run {
                    iconImage = Image(uiImage: uiImage)
                }
                return true
            } catch is CancellationError {
                return true
            } catch {
                dependencies.logger.debug(
                    "Failed to load source icon for \(iconURL.absoluteString): \(String(describing: error))"
                )
            }
        }

        return false
    }

    private func fetchSourceHomeHTML(from url: URL) async -> String? {
        do {
            let response = try await dependencies.httpClient.execute(
                HTTPRequest(
                    url: url,
                    headers: [
                        "Accept": "text/html, application/xhtml+xml;q=0.9, */*;q=0.1",
                        "User-Agent": "RSSReader/0 (Source Icon Discovery)"
                    ],
                    timeoutInterval: 8
                )
            )
            guard (200...299).contains(response.statusCode) else { return nil }
            return String(data: response.body, encoding: .utf8)
        } catch {
            dependencies.logger.debug(
                "Failed to load source homepage for icon discovery from \(url.absoluteString): \(String(describing: error))"
            )
            return nil
        }
    }
}

private struct SourceIconCacheOnlyLoadID: Hashable {
    let siteURL: String?
    let iconURL: String?
    let sidebarReloadID: UUID
}

enum SourceIconCandidateBuilder {
    static func originURL(for url: URL) -> URL? {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme != nil,
              components.host != nil else {
            return nil
        }

        components.path = "/"
        components.query = nil
        components.fragment = nil
        return components.url
    }

    static func commonIconCandidates(for url: URL) -> [URL] {
        guard let originURL = originURL(for: url) else { return [] }

        return deduplicated(
            [
                appendingIconPath("/apple-touch-icon.png", to: originURL),
                appendingIconPath("/apple-touch-icon-precomposed.png", to: originURL),
                appendingIconPath("/favicon-32x32.png", to: originURL),
                appendingIconPath("/favicon.png", to: originURL),
                appendingIconPath("/favicon.ico", to: originURL)
            ].compactMap { $0 }
        )
    }

    static func htmlIconCandidates(in html: String, baseURL: URL) -> [URL] {
        guard let linkTagExpression = try? NSRegularExpression(
            pattern: #"<link\b[^>]*>"#,
            options: [.caseInsensitive]
        ) else {
            return []
        }

        let nsRange = NSRange(html.startIndex..<html.endIndex, in: html)
        let candidates = linkTagExpression.matches(in: html, range: nsRange).compactMap { match -> SourceIconCandidate? in
            guard let tagRange = Range(match.range, in: html) else { return nil }
            let attributes = linkTagAttributes(in: String(html[tagRange]))
            guard let href = attributes["href"],
                  let rel = attributes["rel"],
                  let priority = iconPriority(forRelValue: rel),
                  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL,
                  isSupportedIconURL(url) else {
                return nil
            }

            return SourceIconCandidate(url: url, priority: priority)
        }

        return deduplicated(
            candidates
                .sorted { lhs, rhs in
                    lhs.priority == rhs.priority
                        ? lhs.url.absoluteString < rhs.url.absoluteString
                        : lhs.priority < rhs.priority
                }
                .map(\.url)
        )
    }

    private struct SourceIconCandidate {
        let url: URL
        let priority: Int
    }

    private static func iconPriority(forRelValue relValue: String) -> Int? {
        let tokens = Set(relValue.lowercased().split(whereSeparator: \.isWhitespace).map(String.init))

        if tokens.contains("apple-touch-icon") || tokens.contains("apple-touch-icon-precomposed") {
            return 0
        }

        if tokens.contains("icon") || tokens.contains("shortcut") && tokens.contains("icon") {
            return 1
        }

        return nil
    }

    private static func isSupportedIconURL(_ url: URL) -> Bool {
        url.pathExtension.lowercased() != "svg"
    }

    private static func appendingIconPath(_ path: String, to originURL: URL) -> URL? {
        URL(string: path, relativeTo: originURL)?.absoluteURL
    }

    private static func deduplicated(_ urls: [URL]) -> [URL] {
        var seen = Set<String>()
        return urls.filter { url in
            seen.insert(url.absoluteString).inserted
        }
    }

    private static func linkTagAttributes(in tag: String) -> [String: String] {
        guard let attributeExpression = try? NSRegularExpression(
            pattern: #"([A-Za-z_:][-A-Za-z0-9_:.]*)\s*=\s*("[^"]*"|'[^']*'|[^\s"'>]+)"#,
            options: [.caseInsensitive]
        ) else {
            return [:]
        }

        let nsRange = NSRange(tag.startIndex..<tag.endIndex, in: tag)
        return attributeExpression.matches(in: tag, range: nsRange).reduce(into: [String: String]()) { result, match in
            guard match.numberOfRanges == 3,
                  let nameRange = Range(match.range(at: 1), in: tag),
                  let valueRange = Range(match.range(at: 2), in: tag) else {
                return
            }

            let name = String(tag[nameRange]).lowercased()
            let rawValue = String(tag[valueRange])
            result[name] = unquotedAttributeValue(rawValue)
        }
    }

    private static func unquotedAttributeValue(_ value: String) -> String {
        guard value.count >= 2,
              let first = value.first,
              let last = value.last,
              (first == "\"" && last == "\"") || (first == "'" && last == "'") else {
            return value
        }

        return String(value.dropFirst().dropLast())
    }
}

enum SourceIconImagePolicy {
    static func isSuitableIconSize(_ size: CGSize) -> Bool {
        guard size.width > 0, size.height > 0 else { return false }

        let aspectRatio = max(size.width, size.height) / min(size.width, size.height)
        return aspectRatio <= 2
    }
}
