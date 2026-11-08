import Foundation

/// Owns save continuations independently of the modal and ephemeral router values.
@MainActor
final class FeedSaveRefreshScheduler {
    private var tasks: [UUID: Task<Void, Never>] = [:]

    func schedule(
        id feedID: UUID,
        initialFetchSnapshot: FeedInitialFetchSnapshot?,
        using appState: AppState,
        refresh: @escaping @MainActor (UUID, FeedInitialFetchSnapshot?) async -> Void
    ) {
        // One continuation per pending feed save; the refresh service retains its own single-flight policy.
        guard tasks[feedID] == nil else { return }

        tasks[feedID] = Task { @MainActor in
            defer { tasks[feedID] = nil }
            await refresh(feedID, initialFetchSnapshot)
            appState.requestSidebarReload()
            appState.requestArticleListReload()
        }
    }

    func waitForAll() async {
        // Keep tasks registered while awaiting, so concurrent waiters observe the same work.
        while tasks.isEmpty == false {
            for task in Array(tasks.values) {
                await task.value
            }
        }
    }
}
