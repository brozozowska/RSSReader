import SwiftUI

/// Defers a retaining reload while the native detail route covers the list.
/// Query/session ownership stays in ArticlesScreenController.
@MainActor
final class ArticleListCoverageLifecycle {
    private(set) var hasDeferredLoad = false
    private var resumeTask: Task<Void, Never>?
    private var resumeID: UUID?

    func deferLoad(suspend: () -> Void) {
        cancelResume()
        hasDeferredLoad = true
        suspend()
    }

    func resume(
        canResume: @escaping @MainActor () -> Bool,
        load: @escaping @MainActor () async -> Void,
        delay: @escaping @MainActor () async throws -> Void = {
            try await Task.sleep(for: .milliseconds(400))
        }
    ) {
        guard hasDeferredLoad else { return }
        cancelResume()
        let id = UUID()
        resumeID = id
        resumeTask = Task { @MainActor [weak self] in
            defer { self?.finishResume(id: id) }
            do { try await delay() } catch { return }
            guard Task.isCancelled == false, let self,
                  self.resumeID == id, canResume() else { return }
            self.hasDeferredLoad = false
            await load()
        }
    }

    func endPresentation() {
        cancelResume()
        hasDeferredLoad = false
    }

    func cancelResume() {
        resumeTask?.cancel()
        resumeTask = nil
        resumeID = nil
    }

    private func finishResume(id: UUID) {
        guard resumeID == id else { return }
        resumeTask = nil
        resumeID = nil
    }
}

struct ArticleListPresentationLifecycleModifier: ViewModifier {
    @Environment(AppState.self) private var appState
    @State private var lifecycle = ArticleListCoverageLifecycle()
    let controller: ArticlesScreenController
    let loadContext: ArticleListLoadContext
    let isPreviewMode: Bool
    let searchFocus: FocusState<Bool>.Binding
    let loadArticles: (ArticlesScreenLoadPolicy) async -> Void

    func body(content: Content) -> some View {
        content
            .task(id: loadContext) {
                let searchLifecycle = ArticleListSearchLifecycleState(
                    retainedSelection: loadContext.sidebarSelection,
                    presentedSelection: appState.presentedSidebarSelection
                )
                guard isPreviewMode == false, searchLifecycle.allowsQueryLoad else { return }
                if appState.isArticleListCoveredByDetailRoute {
                    deferLoad()
                } else if lifecycle.hasDeferredLoad {
                    resumeLoad()
                } else {
                    await loadArticles(.retainSession)
                }
            }
            .onChange(of: appState.presentedSidebarSelection) { _, selection in
                guard selection == nil else { return }
                searchFocus.wrappedValue = false
                lifecycle.endPresentation()
            }
            .onChange(of: loadContext.sidebarSelection) { oldValue, newValue in
                guard oldValue != newValue else { return }
                searchFocus.wrappedValue = false
                controller.selectSearchScope(newValue)
            }
            .onChange(of: appState.isArticleListCoveredByDetailRoute) { wasCovered, isCovered in
                guard isPreviewMode == false else { return }
                if isCovered {
                    deferLoad()
                } else if wasCovered {
                    resumeLoad()
                }
            }
            .onDisappear { lifecycle.cancelResume() }
    }

    private func deferLoad() {
        lifecycle.deferLoad { _ = controller.suspendLoadsForCoveredArticleList() }
    }

    private func resumeLoad() {
        lifecycle.resume(
            canResume: {
                appState.isArticleListCoveredByDetailRoute == false
                    && appState.presentedSidebarSelection != nil
            },
            load: { await loadArticles(.resumeMaterializedSession) }
        )
    }
}
