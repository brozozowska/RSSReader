import Foundation

struct ArticleListNextPageIdentity: Equatable {
    let generation: Int
    let sessionID: UUID
    let context: ArticleListSession.Context
    let cursor: ArticleSearchRequest.Cursor
}

/// List and Reader callers share one flight. Cancelling a waiter does not cancel it.
@MainActor
final class ArticlesScreenContinuationLifecycle {
    private var task: Task<ArticleListContinuationSnapshot?, Never>?
    private var identity: ArticleListNextPageIdentity?
    private var flightID: UUID?

    var isActive: Bool { task != nil }

    func activeTask(
        for identity: ArticleListNextPageIdentity
    ) -> Task<ArticleListContinuationSnapshot?, Never>? {
        self.identity == identity ? task : nil
    }

    func cancel() {
        task?.cancel()
        task = nil
        identity = nil
        flightID = nil
    }

    func start(
        identity: ArticleListNextPageIdentity,
        operation: @escaping @MainActor () async -> ArticleListContinuationSnapshot?
    ) -> Task<ArticleListContinuationSnapshot?, Never> {
        precondition(task == nil)
        let flightID = UUID()
        self.identity = identity
        self.flightID = flightID
        let task = Task { @MainActor [weak self] in
            defer { self?.finish(flightID: flightID) }
            return await operation()
        }
        self.task = task
        return task
    }

    private func finish(flightID: UUID) {
        guard self.flightID == flightID else { return }
        task = nil
        identity = nil
        self.flightID = nil
    }
}
