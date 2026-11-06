import Foundation
import Observation
import SwiftUI
import Synchronization
import Testing
@testable import RSSReader

@Suite("Shell / App State Ownership")
@MainActor
struct AppStateOwnershipTests {
    @Test
    func facadeAndOwnerReadsDeliverObservationForEveryPartition() {
        let state = AppState()
        let session = ArticleListSessionReference(id: UUID(), sidebarSelection: .inbox, sidebarArticleFilter: .allItems)
        let checks: [(read: () -> Void, mutate: () -> Void)] = [
            ({ _ = state.presentedSidebarSelection }, { state.selectSidebarSelection(.inbox) }),
            ({ _ = state.readingNavigation.sidebarArticleFilter }, { state.selectSidebarArticleFilter(.unread) }),
            ({ _ = state.isPresentingSettingsScreen }, { state.presentSettingsScreen() }),
            ({ _ = state.presentation.feedManagementLaunchContext }, { state.presentFeedManagementScreen(launchContext: .editFeed(UUID())) }),
            ({ _ = state.pendingFeedUnsubscribeConfirmation }, { state.presentFeedUnsubscribeConfirmation(feedID: UUID(), feedTitle: "News") }),
            ({ _ = state.confirmations.pendingFolderDeleteConfirmation }, { state.presentFolderDeleteConfirmation(folderName: "News") }),
            ({ _ = state.sidebarReloadID }, { state.requestRemoteSyncImportReload() }),
            ({ _ = state.reload.articleListReloadID }, { state.requestBackgroundRefreshReload() }),
            ({ _ = state.interfaceThemeMode }, { state.applyInterfaceThemeMode(.dark) }),
            ({ _ = state.runtime.iCloudSyncStatus }, { state.applyICloudSyncStatus(.syncing) }),
            ({ _ = state.currentArticleListSessionReference }, {
                state.updateArticleNavigationContext([UUID()], sidebarSelection: .inbox, sidebarArticleFilter: .allItems, articleListSessionID: session.id)
            }),
            ({ _ = state.articleListNavigation.readOnOpenEvent }, { state.recordArticleReadOnOpen(UUID(), isRead: true, in: session) })
        ]
        for check in checks {
            #expect(observedChanges(read: check.read, mutate: check.mutate) == 1)
        }
    }

    @Test
    func unrelatedPartitionsDoNotInvalidatePresentationOrNavigationReaders() {
        let state = AppState()
        #expect(observedChanges(read: { _ = state.presentation.isPresentingSettingsScreen }, mutate: {
            state.requestSidebarReload()
            state.applyICloudSyncStatus(.syncing)
            state.presentFolderDeleteConfirmation(folderName: "News")
        }) == 0)
        #expect(observedChanges(read: { _ = state.selectedArticleID }, mutate: {
            state.presentSettingsScreen()
            state.requestArticleListReload()
        }) == 0)
    }

    @Test
    func bindingsRetainNavigationAndModalDismissalOutcomes() {
        let state = AppState()
        @Bindable var bindableState = state
        let sidebar = $bindableState.presentedSidebarSelection
        let article = $bindableState.selectedArticleID
        let settings = Binding(
            get: { state.presentation.isPresentingSettingsScreen },
            set: { $0 ? state.presentSettingsScreen() : state.dismissSettingsScreen() }
        )
        let articleID = UUID()
        sidebar.wrappedValue = .inbox
        article.wrappedValue = articleID
        settings.wrappedValue = true
        settings.wrappedValue = false
        #expect(state.selectedDetailRoute == .article(articleID))
        #expect(state.presentation.isPresentingSettingsScreen == false)

        article.wrappedValue = nil
        sidebar.wrappedValue = nil
        #expect(state.selectedSidebarSelection == .inbox)
        #expect(state.presentedSidebarSelection == nil)
        #expect(state.selectedDetailRoute == .none)
        #expect(state.currentArticleListSessionReference == nil)
    }

    @Test
    func confirmationReplacementAndTypeSpecificCancellationShareOnePayload() {
        var state = AppConfirmationState()
        let feedID = UUID()
        state.presentFeedUnsubscribeConfirmation(feedID: feedID, feedTitle: "Feed")
        state.presentFolderDeleteConfirmation(folderName: "Folder")
        state.dismissFeedUnsubscribeConfirmation()
        #expect(state.pendingFeedUnsubscribeConfirmation == nil)
        #expect(state.pendingFolderDeleteConfirmation?.folderName == "Folder")
        state.presentFeedUnsubscribeConfirmation(feedID: feedID, feedTitle: "Feed")
        state.dismissFolderDeleteConfirmation()
        #expect(state.pendingFolderDeleteConfirmation == nil)
        #expect(state.pendingFeedUnsubscribeConfirmation?.feedID == feedID)
        state.dismissFeedUnsubscribeConfirmation()
        #expect(state.pendingFeedUnsubscribeConfirmation == nil)
    }

    @Test
    func modalOwnerResetsLaunchContextWithoutDismissingIndependentSettings() {
        var state = AppPresentationState()
        state.presentSettingsScreen()
        state.presentFeedManagementScreen(launchContext: .editFeed(UUID()))
        state.dismissFeedManagementScreen()
        #expect(state.isPresentingSettingsScreen)
        #expect(state.isPresentingFeedManagementScreen == false)
        #expect(state.feedManagementLaunchContext == .entry)
        state.presentFeedManagementScreen()
        #expect(state.feedManagementLaunchContext == .entry)
    }

    @Test
    func contentReloadCorrelatesTokensAndKeepsIconInvalidationIndependent() {
        var state = AppReloadState()
        let initial = state
        state.requestContentReload(.remoteSyncImport)
        #expect(state.lastContentReloadTrigger == .remoteSyncImport)
        #expect(state.sidebarReloadID != initial.sidebarReloadID)
        #expect(state.articleListReloadID != initial.articleListReloadID)
        #expect(state.articleScreenReloadID != initial.articleScreenReloadID)
        #expect(state.feedIconCacheResetID == initial.feedIconCacheResetID)
        let content = state
        state.requestFeedIconCacheReset()
        #expect(state.feedIconCacheResetID != content.feedIconCacheResetID)
        #expect(state.sidebarReloadID == content.sidebarReloadID)
        #expect(state.articleListReloadID == content.articleListReloadID)
        #expect(state.articleScreenReloadID == content.articleScreenReloadID)
        #expect(state.lastContentReloadTrigger == content.lastContentReloadTrigger)
    }

    @Test
    func listOwnerPreservesOriginatingEventWhileSameScopeHasANewSession() {
        var state = ArticleListNavigationState()
        let articleID = UUID()
        let oldSession = ArticleListSessionReference(id: UUID(), sidebarSelection: .inbox, sidebarArticleFilter: .unread)
        let newSessionID = UUID()
        state.updateContext([articleID, articleID], sidebarSelection: .inbox, sidebarArticleFilter: .unread, articleListSessionID: newSessionID)
        state.recordReadOnOpen(articleID, isRead: true, in: oldSession)
        #expect(state.articleIDs == [articleID])
        #expect(state.currentSessionReference?.id == newSessionID)
        #expect(state.readOnOpenEvent?.articleListSessionID == oldSession.id)
        state.clearContext(sidebarSelection: .inbox, sidebarArticleFilter: .unread)
        #expect(state.currentSessionReference == nil)
        #expect(state.articleIDs.isEmpty)
        #expect(state.readOnOpenEvent?.articleListSessionID == oldSession.id)
    }

    private func observedChanges(read: () -> Void, mutate: () -> Void) -> Int {
        let changes = Mutex(0)
        withObservationTracking(read, onChange: { changes.withLock { $0 += 1 } })
        mutate()
        return changes.withLock { $0 }
    }
}
