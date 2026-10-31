import SwiftUI
import Testing
@testable import RSSReader

@Suite("Reader / Navigation Coordinator")
@MainActor
struct ReaderArticleNavigationCoordinatorTests {
    @Test
    func overscrollCommitsOnceOnReleaseAndHapticsOncePerGesture() {
        let coordinator = ReaderArticleNavigationCoordinator()
        _ = coordinator.updateScrollPhase(oldPhase: .idle, newPhase: .interacting, isEnabled: true)
        let ready = ReaderArticleScrollGeometry(contentHeight: 1400, containerHeight: 700, boundsMaxY: 1470)
        coordinator.updateOverscroll(ready, isEnabled: true, hasPrevious: true, hasNext: true)
        coordinator.updateOverscroll(ready, isEnabled: true, hasPrevious: true, hasNext: true)
        #expect(coordinator.readyHapticTrigger == 1)
        #expect(coordinator.updateScrollPhase(oldPhase: .interacting, newPhase: .decelerating, isEnabled: true) == .next)
        #expect(coordinator.overscrollState.readyDirection == nil)
        #expect(coordinator.updateScrollPhase(oldPhase: .decelerating, newPhase: .idle, isEnabled: true) == nil)
        _ = coordinator.updateScrollPhase(oldPhase: .idle, newPhase: .interacting, isEnabled: true)
        coordinator.updateOverscroll(ready, isEnabled: true, hasPrevious: false, hasNext: false)
        #expect(coordinator.updateScrollPhase(oldPhase: .interacting, newPhase: .idle, isEnabled: true) == nil)
        #expect(coordinator.readyHapticTrigger == 1)
    }

    @Test
    func disablingSwipesClearsReadyRelease() {
        let coordinator = ReaderArticleNavigationCoordinator()
        coordinator.updateOverscroll(
            ReaderArticleScrollGeometry(containerHeight: 700, contentOffsetY: -100),
            isEnabled: true, hasPrevious: true, hasNext: false
        )
        #expect(coordinator.overscrollState.readyDirection == .previous)
        #expect(coordinator.updateScrollPhase(oldPhase: .interacting, newPhase: .idle, isEnabled: false) == nil)
        #expect(coordinator.overscrollState == ReaderArticleOverscrollNavigationState())
        #expect(coordinator.animation(reduceMotion: true) == nil)
    }

    @Test
    func rapidAdjacentNavigationPreservesNewestTransitionAndSession() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState()
        let ids = [UUID(), UUID(), UUID()]
        appState.selectSidebarSelection(.inbox)
        appState.updateArticleNavigationContext(ids, sidebarSelection: .inbox, sidebarArticleFilter: .allItems,
            articleListSessionID: UUID())
        appState.selectArticle(ids[0])
        let coordinator = ReaderArticleNavigationCoordinator()
        let controller = ArticleScreenController()
        var navigated: [UUID] = []
        var sessions: [ArticleListSessionReference?] = []
        let context = makeContext(appState, controller, harness.dependencies, didNavigate: { id, _, session in
            navigated.append(id)
            sessions.append(session)
        })
        coordinator.navigate(.next, context: context)
        let firstTransition = try #require(coordinator.transition)
        coordinator.navigate(.next, context: context)
        let secondTransition = try #require(coordinator.transition)
        #expect(firstTransition.generation != secondTransition.generation)
        #expect(appState.selectedArticleID == ids[2])
        #expect(navigated == [ids[1], ids[2]])
        #expect(sessions == [context.listSession, context.listSession])
        // Completion for the first target cannot clear the second transition.
        await coordinator.load(articleID: ids[1], transition: firstTransition, context: context)
        #expect(coordinator.transition == secondTransition)
        coordinator.cancelPendingTasks()
        #expect(coordinator.transition == nil)
    }

    @Test
    func continuationIsSingleFlightAndRejectsReplacedSession() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appState = AppState(), controller = ArticleScreenController()
        let source = UUID(), target = UUID()
        appState.selectSidebarSelection(.inbox)
        appState.updateArticleNavigationContext([source], sidebarSelection: .inbox, sidebarArticleFilter: .allItems,
            articleListSessionID: UUID())
        appState.selectArticle(source)
        let started = AsyncTestGate(), release = AsyncTestGate()
        var calls = 0, navigated = false
        let coordinator = ReaderArticleNavigationCoordinator()
        let context = makeContext(appState, controller, harness.dependencies, loadContinuation: { _ in
            calls += 1
            started.release()
            try? await release.wait(honorsCancellation: false)
            return target
        }, didNavigate: { _, _, _ in navigated = true })
        coordinator.navigate(.next, context: context)
        coordinator.navigate(.next, context: context)
        try await started.wait()
        // Same selection/article, but a fresh list identity: old continuation is stale.
        appState.updateArticleNavigationContext([source, target], sidebarSelection: .inbox,
            sidebarArticleFilter: .allItems, articleListSessionID: UUID())
        release.release()
        try await waitUntil("continuation cleanup") { coordinator.isLoadingContinuation == false }
        #expect(calls == 1)
        #expect(navigated == false)
        #expect(appState.selectedArticleID == source)
        #expect(coordinator.transition == nil)
    }

    private func makeContext(
        _ appState: AppState,
        _ controller: ArticleScreenController,
        _ dependencies: AppDependencies,
        loadContinuation: @escaping @MainActor (ReaderAdjacentArticleNavigationDirection) async -> UUID? = { _ in nil },
        didNavigate: @escaping @MainActor (UUID, ReaderAdjacentArticleNavigationDirection, ArticleListSessionReference?) -> Void = { _, _, _ in }
    ) -> ReaderArticleNavigationContext {
        ReaderArticleNavigationContext(
            appState: appState, controller: controller, dependencies: dependencies,
            canLoadContinuation: true, loadContinuation: loadContinuation, didNavigate: didNavigate,
            readOnOpen: nil, updateImagePrefetch: {}
        )
    }
}
