import SwiftUI
import Observation

/// Screen-local gesture/transition lifetime. AppState still owns routes and the
/// Articles controller still owns list sessions, continuation and scroll.
@MainActor
@Observable
final class ReaderArticleNavigationCoordinator {
    private(set) var transition: ReaderAdjacentArticleTransitionContext?
    private(set) var overscrollState = ReaderArticleOverscrollNavigationState()
    private(set) var readyHapticTrigger = 0
    private(set) var isLoadingContinuation = false
    private var transitionGeneration = 0
    private var pendingDirection: ReaderAdjacentArticleNavigationDirection?
    private var didTriggerReadyHaptic = false
    @ObservationIgnored private var continuationTask: Task<Void, Never>?
    @ObservationIgnored private var transitionLoadTask: Task<Void, Never>?
    @ObservationIgnored private var continuationID: UUID?
    @ObservationIgnored private var transitionLoadID: UUID?

    func animation(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : .easeInOut(duration: 0.28)
    }

    func articleTransition(reduceMotion: Bool) -> AnyTransition {
        guard reduceMotion == false else { return .opacity }
        return switch transition?.direction {
        case .next:
            .asymmetric(insertion: .move(edge: .bottom), removal: .move(edge: .top))
        case .previous:
            .asymmetric(insertion: .move(edge: .top), removal: .move(edge: .bottom))
        case .none:
            .opacity
        }
    }

    func activeTransition(targetArticleID: UUID?) -> ReaderAdjacentArticleTransitionContext? {
        guard transition?.targetArticleID == targetArticleID else { return nil }
        return transition
    }

    func updateOverscroll(
        _ geometry: ReaderArticleScrollGeometry,
        isEnabled: Bool,
        hasPrevious: Bool,
        hasNext: Bool
    ) {
        guard isEnabled else {
            resetOverscroll()
            return
        }
        let proposed = ArticleScreenNavigationState.adjacentArticleOverscrollState(scrollGeometry: geometry)
        let newState = ReaderArticleOverscrollNavigationState(
            previousProgress: hasPrevious ? proposed.previousProgress : 0,
            nextProgress: hasNext ? proposed.nextProgress : 0
        )
        if ArticleScreenNavigationState.shouldTriggerAdjacentArticleOverscrollReadyHaptic(
            previousState: overscrollState,
            newState: newState,
            hasTriggeredInCurrentGesture: didTriggerReadyHaptic
        ) {
            readyHapticTrigger += 1
            didTriggerReadyHaptic = true
        }
        overscrollState = newState
        pendingDirection = newState.readyDirection
    }

    func updateScrollPhase(
        oldPhase: ScrollPhase,
        newPhase: ScrollPhase,
        isEnabled: Bool
    ) -> ReaderAdjacentArticleNavigationDirection? {
        guard isEnabled else {
            resetOverscroll()
            return nil
        }
        if newPhase == .tracking || newPhase == .interacting {
            resetOverscroll()
            didTriggerReadyHaptic = false
            return nil
        }
        guard oldPhase == .interacting, newPhase != .interacting else { return nil }
        let direction = pendingDirection
        resetOverscroll()
        return direction
    }

    func navigate(_ direction: ReaderAdjacentArticleNavigationDirection, context: ReaderArticleNavigationContext) {
        guard let sourceID = context.appState.selectedArticleID else { return }
        if let targetID = context.appState.adjacentArticleID(direction) {
            performNavigation(direction, sourceID: sourceID, targetID: targetID, context: context)
            return
        }
        guard direction == .next, context.canLoadContinuation, isLoadingContinuation == false else { return }
        isLoadingContinuation = true
        let id = UUID()
        continuationID = id
        continuationTask = Task { @MainActor in
            defer { self.finishContinuation(id: id) }
            let targetID = await context.loadContinuation(direction)
            guard Task.isCancelled == false, context.isCurrent(articleID: sourceID),
                  let targetID else { return }
            self.performNavigation(direction, sourceID: sourceID, targetID: targetID, context: context)
        }
    }

    func load(
        articleID: UUID?,
        transition: ReaderAdjacentArticleTransitionContext?,
        context: ReaderArticleNavigationContext
    ) async {
        await context.controller.load(
            articleID: articleID,
            dependencies: context.dependencies,
            preservesCurrentArticleDuringLoading: transition != nil,
            articleReadOnOpenHandler: context.readOnOpen
        )
        guard Task.isCancelled == false, context.isCurrent(articleID: articleID),
              self.transition == transition else { return }
        resetOverscroll()
        await finishTransitionAfterAnimation(transition)
    }

    func cancelPendingTasks() {
        continuationTask?.cancel()
        transitionLoadTask?.cancel()
        continuationTask = nil
        transitionLoadTask = nil
        continuationID = nil
        transitionLoadID = nil
        isLoadingContinuation = false
        transition = nil
        resetOverscroll()
    }

    private func finishContinuation(id: UUID) {
        guard continuationID == id else { return }
        continuationTask = nil
        continuationID = nil
        isLoadingContinuation = false
    }

    private func finishTransitionLoad(id: UUID) {
        guard transitionLoadID == id else { return }
        transitionLoadTask = nil
        transitionLoadID = nil
    }

    private func resetOverscroll() {
        pendingDirection = nil
        overscrollState = ReaderArticleOverscrollNavigationState()
    }

    private func performNavigation(
        _ direction: ReaderAdjacentArticleNavigationDirection,
        sourceID: UUID,
        targetID: UUID,
        context: ReaderArticleNavigationContext
    ) {
        guard context.isCurrent(articleID: sourceID),
              context.appState.adjacentArticleID(direction) == targetID else { return }
        transitionGeneration += 1
        let transition = ReaderAdjacentArticleTransitionContext(
            generation: transitionGeneration, direction: direction,
            sourceArticleID: sourceID, targetArticleID: targetID
        )
        self.transition = transition
        guard context.appState.selectAdjacentArticle(direction) else {
            clearTransition(transition)
            return
        }
        context.didNavigate(targetID, direction, context.listSession)
        context.updateImagePrefetch()
        transitionLoadTask?.cancel()
        let id = UUID()
        transitionLoadID = id
        transitionLoadTask = Task { @MainActor in
            defer { self.finishTransitionLoad(id: id) }
            do {
                try await Task.sleep(for: .milliseconds(80))
            } catch { return }
            guard self.transition == transition, context.isCurrent(articleID: targetID) else { return }
            if context.controller.screenState.article?.id == targetID {
                await self.finishTransitionAfterAnimation(transition)
            } else {
                await self.load(articleID: targetID, transition: transition, context: context)
            }
        }
    }

    private func finishTransitionAfterAnimation(_ transition: ReaderAdjacentArticleTransitionContext?) async {
        guard let transition, self.transition == transition else { return }
        do {
            try await Task.sleep(for: .milliseconds(320))
        } catch { return }
        clearTransition(transition)
    }

    private func clearTransition(_ transition: ReaderAdjacentArticleTransitionContext) {
        guard self.transition == transition else { return }
        self.transition = nil
    }
}

struct ReaderAdjacentArticleTransitionContext: Equatable {
    let generation: Int
    let direction: ReaderAdjacentArticleNavigationDirection
    let sourceArticleID: UUID
    let targetArticleID: UUID
}

@MainActor
struct ReaderArticleNavigationContext {
    let appState: AppState
    let controller: ArticleScreenController
    let dependencies: AppDependencies
    let canLoadContinuation: Bool
    let loadContinuation: @MainActor (ReaderAdjacentArticleNavigationDirection) async -> UUID?
    let didNavigate: @MainActor (UUID, ReaderAdjacentArticleNavigationDirection, ArticleListSessionReference?) -> Void
    let readOnOpen: ArticleReadOnOpenHandler?
    let updateImagePrefetch: () -> Void
    let listSession: ArticleListSessionReference?

    init(
        appState: AppState,
        controller: ArticleScreenController,
        dependencies: AppDependencies,
        canLoadContinuation: Bool,
        loadContinuation: @escaping @MainActor (ReaderAdjacentArticleNavigationDirection) async -> UUID?,
        didNavigate: @escaping @MainActor (UUID, ReaderAdjacentArticleNavigationDirection, ArticleListSessionReference?) -> Void,
        readOnOpen: ArticleReadOnOpenHandler?,
        updateImagePrefetch: @escaping () -> Void
    ) {
        self.appState = appState
        self.controller = controller
        self.dependencies = dependencies
        self.canLoadContinuation = canLoadContinuation
        self.loadContinuation = loadContinuation
        self.didNavigate = didNavigate
        self.readOnOpen = readOnOpen
        self.updateImagePrefetch = updateImagePrefetch
        self.listSession = appState.currentArticleListSessionReference
    }

    func isCurrent(articleID: UUID?) -> Bool {
        appState.selectedArticleID == articleID && appState.currentArticleListSessionReference == listSession
    }
}
