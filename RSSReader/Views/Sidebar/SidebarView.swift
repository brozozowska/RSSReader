import SwiftUI
import SwiftData
import UIKit

struct SidebarView: View {
    // MARK: Dependencies

    @Environment(\.appDependencies) private var dependencies
    @Environment(AppState.self) private var appState

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
        let viewState = controller.viewState(filter: appState.selectedSourcesFilter)

        List(selection: $selection) {
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
                subtitleView(toolbarState: viewState.toolbarState)
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
            guard controller.isPreviewMode == false else { return }
            await loadFeeds(showsFullScreenLoading: true, refreshedAt: .now)
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
            SourceIconView(iconURL: row.iconURL)

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
