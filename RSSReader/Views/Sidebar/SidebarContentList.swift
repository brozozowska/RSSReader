import SwiftUI

struct SidebarContentList: View {
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

private struct SidebarSections: View {
    @Binding var selection: SidebarSelection?
    let viewState: SidebarScreenDerivedViewState
    let actionHandlers: SidebarActionHandlers
    let onFolderExpansionToggle: (String) -> Void

    var body: some View {
        if viewState.smartRows.isEmpty == false {
            Section {
                ForEach(viewState.smartRows) { row in
                    SidebarSmartRowView(row: row, selection: $selection)
                }
            } header: {
                if viewState.smartRows.count > 1 {
                    SidebarSectionHeader(title: "Smart Views")
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
                SidebarSectionHeader(title: "Folders")
            }
        }

        if viewState.ungroupedFeedRows.isEmpty == false {
            Section {
                ForEach(viewState.ungroupedFeedRows) { feed in
                    SidebarFeedRowView(
                        row: feed,
                        selection: $selection,
                        actionHandlers: actionHandlers
                    )
                }
            } header: {
                SidebarSectionHeader(title: "Ungrouped")
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
                selection: $selection,
                actionHandlers: actionHandlers
            )
        }
    }
}
