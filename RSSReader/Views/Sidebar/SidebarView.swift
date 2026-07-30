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
        .alert(
            SidebarLocalization.unsubscribeConfirmationTitle,
            isPresented: feedUnsubscribeConfirmationIsPresented
        ) {
            Button(SidebarLocalization.unsubscribeConfirmationActionTitle, role: .destructive) {
                dependencies.appActions.confirmPendingFeedUnsubscribe(using: appState)
            }
            Button(SidebarLocalization.cancelActionTitle, role: .cancel) {
                dependencies.appActions.cancelFeedUnsubscribeConfirmation(using: appState)
            }
        } message: {
            if let pendingConfirmation = appState.pendingFeedUnsubscribeConfirmation {
                Text(
                    SidebarLocalization.unsubscribeConfirmationMessage(
                        feedTitle: pendingConfirmation.feedTitle
                    )
                )
            }
        }
        .alert(
            SidebarLocalization.folderDeleteConfirmationTitle,
            isPresented: folderDeleteConfirmationIsPresented
        ) {
            Button(SidebarLocalization.folderDeleteConfirmationActionTitle, role: .destructive) {
                dependencies.appActions.confirmPendingFolderDelete(using: appState)
            }
            Button(SidebarLocalization.cancelActionTitle, role: .cancel) {
                dependencies.appActions.cancelFolderDeleteConfirmation(using: appState)
            }
        } message: {
            if let pendingConfirmation = appState.pendingFolderDeleteConfirmation {
                Text(
                    SidebarLocalization.folderDeleteConfirmationMessage(
                        folderName: pendingConfirmation.folderName
                    )
                )
            }
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
        .onChange(of: appState.selectedSidebarArticleFilter) { _, filter in
            let currentSelection = appState.selectedSidebarSelection
            let resolvedSelection = controller.resolvedSelection(
                currentSelection: currentSelection,
                filter: filter
            )
            appState.reconcileSidebarSelection(
                resolvedSelection,
                expectedSelection: currentSelection,
                expectedFilter: filter
            )
        }
        .sensoryFeedback(
            .impact(flexibility: .solid, intensity: 0.65),
            trigger: refreshStartHapticTrigger
        )
    }

    @MainActor
    private func loadFeeds(showsFullScreenLoading: Bool, refreshedAt: Date?) async {
        let currentSelection = appState.selectedSidebarSelection
        let currentFilter = appState.selectedSidebarArticleFilter
        let adjustedSelection = await controller.loadFeeds(
            showsFullScreenLoading: showsFullScreenLoading,
            dependencies: dependencies,
            currentSelection: currentSelection,
            filter: currentFilter,
            refreshedAt: refreshedAt
        )

        appState.reconcileSidebarSelection(
            adjustedSelection,
            expectedSelection: currentSelection,
            expectedFilter: currentFilter
        )
    }

    @MainActor
    private func refreshSidebar() async {
        guard controller.isPreviewMode == false, controller.screenState.isSyncing == false else { return }

        refreshStartHapticTrigger += 1

        let currentSelection = appState.selectedSidebarSelection
        let currentFilter = appState.selectedSidebarArticleFilter
        let adjustedSelection = await controller.refreshSidebar(
            dependencies: dependencies,
            appState: appState,
            currentSelection: currentSelection,
            filter: currentFilter
        )

        appState.reconcileSidebarSelection(
            adjustedSelection,
            expectedSelection: currentSelection,
            expectedFilter: currentFilter
        )
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
            showFeedManagement: {
                dependencies.appActions.showFeedManagement(using: appState)
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
            requestFeedUnsubscribeConfirmation: { feedID, feedTitle in
                dependencies.appActions.requestFeedUnsubscribeConfirmation(
                    id: feedID,
                    title: feedTitle,
                    using: appState
                )
            },
            showFolderEditor: { folderName in
                dependencies.appActions.showFolderEditor(named: folderName, using: appState)
            },
            requestFolderDeleteConfirmation: { folderName in
                dependencies.appActions.requestFolderDeleteConfirmation(
                    named: folderName,
                    using: appState
                )
            }
        )
    }

    private var feedUnsubscribeConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { appState.pendingFeedUnsubscribeConfirmation != nil },
            set: { isPresented in
                if isPresented == false {
                    dependencies.appActions.cancelFeedUnsubscribeConfirmation(using: appState)
                }
            }
        )
    }

    private var folderDeleteConfirmationIsPresented: Binding<Bool> {
        Binding(
            get: { appState.pendingFolderDeleteConfirmation != nil },
            set: { isPresented in
                if isPresented == false {
                    dependencies.appActions.cancelFolderDeleteConfirmation(using: appState)
                }
            }
        )
    }
}
