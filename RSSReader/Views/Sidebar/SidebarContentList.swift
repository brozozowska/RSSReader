import SwiftUI

struct SidebarContentList: View {
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    @Binding var selection: SidebarSelection?
    let viewState: SidebarScreenDerivedViewState
    let customRefreshState: SidebarCustomRefreshState
    let appThemeVariant: AppThemeVariant
    let actionHandlers: SidebarActionHandlers
    let onFolderExpansionToggle: (String) -> Void
    let onCustomRefreshPullProgressChange: (Double) -> Void
    let onCustomRefreshRelease: () -> Void

    var body: some View {
        List(selection: $selection) {
            SidebarSections(
                selection: $selection,
                viewState: viewState,
                actionHandlers: actionHandlers,
                onFolderExpansionToggle: onFolderExpansionToggle
            )
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(appThemeVariant.primaryBackground)
        .scrollDisabled(viewState.shouldDisableScrolling)
        .animation(
            accessibilityReduceMotion ? nil : .snappy(duration: 0.24),
            value: SidebarVisibleContentIdentity(viewState: viewState)
        )
        .onScrollGeometryChange(for: SidebarCustomRefreshGeometry.self) { geometry in
            SidebarCustomRefreshGeometry(
                contentOffsetY: geometry.contentOffset.y,
                contentInsetTop: geometry.contentInsets.top
            )
        } action: { _, newGeometry in
            let progress = SidebarCustomRefreshPullPolicy.progress(for: newGeometry)
            onCustomRefreshPullProgressChange(progress)
        }
        .onScrollPhaseChange { oldPhase, newPhase, _ in
            guard SidebarCustomRefreshReleasePolicy.shouldTriggerRefresh(
                wasInteracting: oldPhase == .interacting,
                isInteracting: newPhase == .interacting,
                customRefreshState: customRefreshState
            ) else {
                return
            }

            onCustomRefreshRelease()
        }
    }
}

private struct SidebarVisibleContentIdentity: Equatable {
    let smartRowIDs: [SmartSidebarItem]
    let folderRowIDs: [String]
    let ungroupedFeedRowIDs: [UUID]

    init(viewState: SidebarScreenDerivedViewState) {
        self.smartRowIDs = viewState.smartRows.map(\.id)
        self.folderRowIDs = viewState.folderRows.map(\.id)
        self.ungroupedFeedRowIDs = viewState.ungroupedFeedRows.map(\.id)
    }
}

private struct SidebarSections: View {
    @Binding var selection: SidebarSelection?
    let viewState: SidebarScreenDerivedViewState
    let actionHandlers: SidebarActionHandlers
    let onFolderExpansionToggle: (String) -> Void

    var body: some View {
        if viewState.smartRows.isEmpty == false {
            Section {
                ForEach(viewState.smartRows) { row in
                    SidebarSmartRowView(row: row)
                }
            } header: {
                if viewState.smartRows.count > 1 {
                    SidebarSectionHeader(title: SidebarLocalization.smartViewsSectionTitle)
                }
            }
        }

        if viewState.folderRows.isEmpty == false {
            Section {
                ForEach(viewState.folderRows) { row in
                    SidebarFolderSectionRowView(
                        row: row,
                        selection: $selection,
                        actionHandlers: actionHandlers,
                        onFolderExpansionToggle: onFolderExpansionToggle
                    )
                }
            } header: {
                SidebarSectionHeader(title: SidebarLocalization.foldersSectionTitle)
            }
        }

        if viewState.ungroupedFeedRows.isEmpty == false {
            Section {
                ForEach(viewState.ungroupedFeedRows) { feed in
                    SidebarFeedRowView(
                        row: feed,
                        actionHandlers: actionHandlers
                    )
                }
            } header: {
                SidebarSectionHeader(title: SidebarLocalization.ungroupedSectionTitle)
            }
        }
    }
}

private struct SidebarFolderSectionRowView: View {
    let row: SidebarFolderSectionRowState
    @Binding var selection: SidebarSelection?
    let actionHandlers: SidebarActionHandlers
    let onFolderExpansionToggle: (String) -> Void

    var body: some View {
        switch row {
        case .folder(let row):
            SidebarFolderRowView(
                row: row,
                selection: $selection,
                actionHandlers: actionHandlers,
                onFolderExpansionToggle: onFolderExpansionToggle
            )
        case .feed(let feed):
            SidebarFeedRowView(
                row: feed,
                actionHandlers: actionHandlers
            )
        }
    }
}
