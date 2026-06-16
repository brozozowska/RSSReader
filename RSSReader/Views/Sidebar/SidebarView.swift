import SwiftUI

struct SidebarView: View {
    @Environment(\.appDependencies) private var dependencies
    @Environment(AppState.self) private var appState
    @Environment(\.appThemeVariant) private var appThemeVariant

    @Binding var selection: SidebarSelection?

    @State private var controller: SidebarScreenController
    @State private var refreshStartHapticTrigger = 0

    init(
        selection: Binding<SidebarSelection?>,
        previewScreenState: SidebarScreenState? = nil
    ) {
        _selection = selection
        self._controller = State(initialValue: SidebarScreenController(previewScreenState: previewScreenState))
    }

    var body: some View {
        let viewState = controller.viewState(
            filter: appState.selectedSidebarArticleFilter,
            iCloudSyncStatus: appState.iCloudSyncStatus
        )

        ZStack {
            SidebarContentList(
                selection: $selection,
                viewState: viewState,
                customRefreshState: controller.screenState.customRefreshState,
                appThemeVariant: appThemeVariant,
                actionHandlers: actionHandlers,
                onFolderExpansionToggle: toggleFolderExpansion,
                onCustomRefreshPullProgressChange: updateCustomRefreshPullProgress,
                onCustomRefreshRelease: triggerCustomRefreshFromScrollRelease
            )

            SidebarCustomRefreshIndicator(
                customRefreshState: controller.screenState.customRefreshState
            )
        }
        .toolbarTitleDisplayMode(.inline)
        .toolbar {
            SidebarToolbarContent(
                toolbarState: viewState.toolbarState,
                selectedSidebarArticleFilter: appState.selectedSidebarArticleFilter,
                actionHandlers: actionHandlers
            )
        }
        .overlay {
            SidebarOverlayContent(viewState: viewState)
        }
        .task {
            guard controller.isPreviewMode == false else { return }
            await loadFeeds(showsFullScreenLoading: true, refreshedAt: nil)
        }
        .onChange(of: appState.sidebarReloadID) { _, _ in
            guard controller.isPreviewMode == false else { return }
            Task {
                await loadFeeds(showsFullScreenLoading: false, refreshedAt: nil)
            }
        }
        .onChange(of: appState.selectedSidebarArticleFilter) { _, _ in
            selection = controller.resolvedSelection(
                currentSelection: selection,
                filter: appState.selectedSidebarArticleFilter
            )
        }
        .sensoryFeedback(
            .impact(flexibility: .solid, intensity: 0.65),
            trigger: refreshStartHapticTrigger
        )
    }

    @MainActor
    private func loadFeeds(showsFullScreenLoading: Bool, refreshedAt: Date?) async {
        let adjustedSelection = await controller.loadFeeds(
            showsFullScreenLoading: showsFullScreenLoading,
            dependencies: dependencies,
            currentSelection: selection,
            filter: appState.selectedSidebarArticleFilter,
            refreshedAt: refreshedAt
        )

        selection = adjustedSelection
    }

    @MainActor
    private func refreshSidebar() async {
        guard controller.isPreviewMode == false, controller.screenState.isSyncing == false else { return }

        refreshStartHapticTrigger += 1

        let adjustedSelection = await controller.refreshSidebar(
            dependencies: dependencies,
            appState: appState,
            currentSelection: selection,
            filter: appState.selectedSidebarArticleFilter
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

        await refreshSidebar()
    }

    @MainActor
    private func toggleFolderExpansion(named folderName: String) {
        controller.toggleFolderExpansion(named: folderName)
    }

    @MainActor
    private func triggerCustomRefreshFromScrollRelease() {
        Task {
            await triggerCustomRefresh()
        }
    }

    private var actionHandlers: SidebarActionHandlers {
        SidebarActionHandlers(
            showSettings: {
                dependencies.appActions.showSettings(using: appState)
            },
            showSourceManagement: {
                dependencies.appActions.showSourceManagement(using: appState)
            },
            applySidebarArticleFilter: { filter in
                dependencies.appActions.applySidebarArticleFilter(filter, using: appState)
            },
            showFeedOrganizer: { feedID in
                dependencies.appActions.showFeedOrganizer(id: feedID, using: appState)
            },
            showFeedEditor: { feedID in
                dependencies.appActions.showFeedEditor(id: feedID, using: appState)
            },
            unsubscribeFeed: { feedID in
                dependencies.appActions.unsubscribeFeed(id: feedID, using: appState)
            },
            showFolder: { folderName in
                dependencies.appActions.showFolder(named: folderName, using: appState)
            },
            showFolderEditor: { folderName in
                dependencies.appActions.showFolderEditor(named: folderName, using: appState)
            },
            deleteFolder: { folderName in
                dependencies.appActions.deleteFolder(named: folderName, using: appState)
            }
        )
    }
}
