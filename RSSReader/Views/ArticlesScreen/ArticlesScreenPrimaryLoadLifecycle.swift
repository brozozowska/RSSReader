import Foundation

/// Owns supersession and cleanup; the controller alone publishes screen snapshots.
@MainActor
final class ArticlesScreenPrimaryLoadLifecycle {
    private(set) var generation = 0
    private var task: Task<Void, Never>?
    private var context: ArticleListSession.Context?

    var isActive: Bool { task != nil }

    func activeTask(for context: ArticleListSession.Context) -> Task<Void, Never>? {
        self.context == context ? task : nil
    }

    func cancel() {
        generation += 1
        task?.cancel()
        task = nil
        context = nil
    }

    func start(
        context: ArticleListSession.Context,
        operation: @escaping @MainActor (Int) async -> Void
    ) -> Task<Void, Never> {
        cancel()
        let generation = generation
        self.context = context
        let task = Task { @MainActor [weak self] in
            defer { self?.finish(generation: generation) }
            await operation(generation)
        }
        self.task = task
        return task
    }

    private func finish(generation: Int) {
        guard generation == self.generation else { return }
        task = nil
        context = nil
    }
}
