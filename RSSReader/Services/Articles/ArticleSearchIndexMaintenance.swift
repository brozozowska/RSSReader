import Foundation
import SwiftData

/// App-owned derived-index maintenance, independent of read-only search queries.
/// Each committed row is a durable checkpoint. A new run skips current rows.
@MainActor
final class ArticleSearchIndexMaintenance {
    private let container: ModelContainer
    private let checkpoint: (Int) async throws -> Void
    private let save: (ModelContext) throws -> Void
    private var flight: Task<Void, Never>?
    private var failure: Error?
    var waitingQueryCount: Int { waiters.count }
    private var waiters: [UUID: CheckedContinuation<Void, Error>] = [:]

    init(
        container: ModelContainer,
        checkpoint: @escaping (Int) async throws -> Void = { _ in },
        save: @escaping (ModelContext) throws -> Void = { try $0.save() }
    ) {
        self.container = container
        self.checkpoint = checkpoint
        self.save = save
    }

    func start() {
        guard flight == nil else { return }
        failure = nil
        flight = Task { [self] in
            let result: Result<Void, Error>
            do { try await rebuild(); result = .success(()) }
            catch { result = .failure(error) }
            if case .failure(let error) = result { failure = error }
            flight = nil
            let pending = waiters.values
            waiters.removeAll()
            for waiter in pending { waiter.resume(with: result) }
        }
    }

    func retry() { start() }

    func waitUntilReady() async throws {
        try Task.checkCancellation()
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else if flight != nil {
                    waiters[id] = continuation
                } else if let failure {
                    continuation.resume(throwing: failure)
                } else {
                    continuation.resume(returning: ())
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.waiters.removeValue(forKey: id)?.resume(throwing: CancellationError())
            }
        }
    }

    func cancel() { flight?.cancel() }

    private func rebuild() async throws {
        var completed = 0
        // Keyset pages bound snapshot retention. A final pass also catches an
        // outdated payload imported/changed behind the cursor during suspension.
        while true {
            var cursor: UUID?
            var foundOutdated = false
            while true {
                try Task.checkCancellation()
                let snapshots = try outdatedArticles(after: cursor)
                guard !snapshots.isEmpty else { break }
                foundOutdated = true
                for snapshot in snapshots {
                    try Task.checkCancellation()
                    let worker = Task.detached(priority: .utility) {
                        try Task.checkCancellation()
                        let index = ArticleSearchableTextPolicy.materialize(snapshot)
                        try Task.checkCancellation()
                        return index
                    }
                    let index = try await withTaskCancellationHandler {
                        try await worker.value
                    } onCancel: { worker.cancel() }
                    try Task.checkCancellation()
                    try commit(index, for: snapshot)
                    completed += 1
                    try await checkpoint(completed)
                    cursor = snapshot.id
                    await Task.yield()
                }
            }
            if !foundOutdated { return }
        }
    }

    private func outdatedArticles(after cursor: UUID?) throws -> [ReaderArticleDTO] {
        let context = container.mainContext
        let prefix = ArticleSearchableTextPolicy.formatPrefix
        let predicate: Predicate<Article>
        if let cursor {
            predicate = #Predicate { !$0.searchableText.starts(with: prefix) && $0.id > cursor }
        } else {
            predicate = #Predicate { !$0.searchableText.starts(with: prefix) }
        }
        var descriptor = FetchDescriptor<Article>(predicate: predicate, sortBy: [SortDescriptor(\Article.id)])
        descriptor.fetchLimit = 16
        return try context.fetch(descriptor).map { ReaderArticleDTO(article: $0, state: nil) }
    }

    private func commit(_ index: String, for snapshot: ReaderArticleDTO) throws {
        // Refetch through the shared repository context after suspension. A concurrent refresh wins;
        // a changed outdated payload will be picked up by the next iteration.
        let context = container.mainContext
        let id = snapshot.id
        var descriptor = FetchDescriptor<Article>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let article = try context.fetch(descriptor).first,
              !article.searchableText.hasPrefix(ArticleSearchableTextPolicy.formatPrefix),
              article.title == snapshot.title, article.author == snapshot.author,
              article.contentHTML == snapshot.contentHTML, article.contentText == snapshot.contentText,
              article.summary == snapshot.summary, article.url == snapshot.articleURL,
              article.canonicalURL == snapshot.canonicalURL, article.feedSiteURL == snapshot.feedSiteURL else { return }
        let previous = article.searchableText
        article.searchableText = index
        do { try save(context) } catch { article.searchableText = previous; throw error }
    }
}

nonisolated enum ArticleSearchIndexError: Error {
    case outdatedIndex
}
