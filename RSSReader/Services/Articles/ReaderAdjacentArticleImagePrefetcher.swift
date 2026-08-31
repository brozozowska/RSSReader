import Foundation

nonisolated struct ReaderAdjacentArticleImagePrefetchContext: Hashable, Sendable {
    let currentArticleID: UUID
    let articleListSessionID: UUID
    let previousCandidateArticleIDs: [UUID]
    let nextCandidateArticleIDs: [UUID]
    let displayTarget: ArticleImageDisplayTarget

    var articleIDs: [UUID] {
        var seen = Set<UUID>()

        return ([currentArticleID] + previousCandidateArticleIDs + nextCandidateArticleIDs)
            .filter { seen.insert($0).inserted }
    }
}

nonisolated struct ReaderAdjacentArticleImagePrefetchPlan: Equatable, Sendable {
    let currentImageURL: URL?
    let adjacentImageURLs: [URL]

    var reservationURLs: [URL] {
        var seen = Set<URL>()
        return ([currentImageURL].compactMap { $0 } + adjacentImageURLs)
            .filter { seen.insert($0).inserted }
    }
}

nonisolated enum ReaderAdjacentArticleImagePrefetchPolicy {
    static let maximumCandidateArticleCountPerDirection = 6
    static let maximumImageCountPerDirection = 2
    static let maximumConcurrentPrefetchCount = 2
    static let maximumReservedImageCount = 1 + (maximumImageCountPerDirection * 2)
}

@MainActor
protocol ArticleImagePrefetching: AnyObject {
    func prefetchImage(from url: URL, displayTarget: ArticleImageDisplayTarget) async
    func replacePrefetchReservations(with urls: [URL])
    func clearPrefetchReservations()
}

extension ArticleImageLoader: ArticleImagePrefetching {}

@MainActor
final class ReaderAdjacentArticleImagePrefetchCoordinator {
    static let shared = ReaderAdjacentArticleImagePrefetchCoordinator(
        imagePrefetcher: ArticleImageLoader.shared
    )

    private let imagePrefetcher: any ArticleImagePrefetching
    private var activeContext: ReaderAdjacentArticleImagePrefetchContext?
    private var activeTasks: [URL: ActivePrefetchTask] = [:]
    private var pendingImageURLs: [URL] = []

    init(imagePrefetcher: any ArticleImagePrefetching) {
        self.imagePrefetcher = imagePrefetcher
    }

    func update(
        context: ReaderAdjacentArticleImagePrefetchContext?,
        articleQueryService: (any ArticleQueryService)?
    ) {
        guard let context, let articleQueryService else { return }

        guard context != activeContext else { return }

        let plan: ReaderAdjacentArticleImagePrefetchPlan
        do {
            plan = try ReaderAdjacentArticleImagePrefetcher.plan(
                context: context,
                articleQueryService: articleQueryService
            )
        } catch {
            activeContext = context
            cancelAllPrefetchTasks()
            imagePrefetcher.replacePrefetchReservations(with: [])
            return
        }

        if let activeContext,
           activeContext.prefetchScope != context.prefetchScope {
            cancelAllPrefetchTasks()
        }
        activeContext = context
        imagePrefetcher.replacePrefetchReservations(with: plan.reservationURLs)

        let relevantImageURLs = Set(plan.reservationURLs)
        cancelPrefetchTasks(notIn: relevantImageURLs)

        pendingImageURLs = plan.adjacentImageURLs.filter { imageURL in
            activeTasks[imageURL] == nil
        }
        schedulePendingPrefetchTasks(displayTarget: context.displayTarget)
    }

    func clear() {
        clearActiveState()
    }

    private func schedulePendingPrefetchTasks(displayTarget: ArticleImageDisplayTarget) {
        while activeTasks.count < ReaderAdjacentArticleImagePrefetchPolicy.maximumConcurrentPrefetchCount,
              pendingImageURLs.isEmpty == false {
            let imageURL = pendingImageURLs.removeFirst()
            let taskID = UUID()
            let imagePrefetcher = imagePrefetcher
            let task = Task(priority: .utility) { @MainActor [weak self] in
                await imagePrefetcher.prefetchImage(
                    from: imageURL,
                    displayTarget: displayTarget
                )
                self?.completePrefetchTask(
                    id: taskID,
                    imageURL: imageURL,
                    displayTarget: displayTarget
                )
            }
            activeTasks[imageURL] = ActivePrefetchTask(id: taskID, task: task)
        }
    }

    private func completePrefetchTask(
        id taskID: UUID,
        imageURL: URL,
        displayTarget: ArticleImageDisplayTarget
    ) {
        guard activeTasks[imageURL]?.id == taskID else { return }
        activeTasks.removeValue(forKey: imageURL)
        schedulePendingPrefetchTasks(displayTarget: displayTarget)
    }

    private func cancelPrefetchTasks(notIn relevantImageURLs: Set<URL>) {
        let obsoleteImageURLs = activeTasks.keys.filter {
            relevantImageURLs.contains($0) == false
        }
        for imageURL in obsoleteImageURLs {
            activeTasks.removeValue(forKey: imageURL)?.task.cancel()
        }
    }

    private func cancelAllPrefetchTasks() {
        for activeTask in activeTasks.values {
            activeTask.task.cancel()
        }
        activeTasks.removeAll()
        pendingImageURLs.removeAll()
    }

    private func clearActiveState() {
        activeContext = nil
        cancelAllPrefetchTasks()
        imagePrefetcher.clearPrefetchReservations()
    }
}

@MainActor
enum ReaderAdjacentArticleImagePrefetcher {
    static func plan(
        context: ReaderAdjacentArticleImagePrefetchContext,
        articleQueryService: any ArticleQueryService
    ) throws -> ReaderAdjacentArticleImagePrefetchPlan {
        let articles = try articleQueryService.fetchReaderArticles(ids: context.articleIDs)
        let articlesByID = Dictionary(uniqueKeysWithValues: articles.map { ($0.id, $0) })
        let currentImageURL = articlesByID[context.currentArticleID].flatMap(firstRenderedImageURL)
        var seenImageURLs = Set<URL>()
        if let currentImageURL {
            seenImageURLs.insert(currentImageURL)
        }

        let previousImageURLs = imageURLs(
            for: context.previousCandidateArticleIDs,
            articlesByID: articlesByID,
            seenImageURLs: &seenImageURLs
        )
        let nextImageURLs = imageURLs(
            for: context.nextCandidateArticleIDs,
            articlesByID: articlesByID,
            seenImageURLs: &seenImageURLs
        )

        return ReaderAdjacentArticleImagePrefetchPlan(
            currentImageURL: currentImageURL,
            adjacentImageURLs: interleaved(previousImageURLs, nextImageURLs)
        )
    }

    private static func imageURLs(
        for articleIDs: [UUID],
        articlesByID: [UUID: ReaderArticleDTO],
        seenImageURLs: inout Set<URL>
    ) -> [URL] {
        var imageURLs: [URL] = []
        for articleID in articleIDs {
            guard imageURLs.count < ReaderAdjacentArticleImagePrefetchPolicy.maximumImageCountPerDirection,
                  let article = articlesByID[articleID],
                  let imageURL = firstRenderedImageURL(for: article),
                  seenImageURLs.insert(imageURL).inserted else {
                continue
            }
            imageURLs.append(imageURL)
        }
        return imageURLs
    }

    private static func interleaved(_ lhs: [URL], _ rhs: [URL]) -> [URL] {
        var result: [URL] = []
        let maximumCount = max(lhs.count, rhs.count)
        for index in 0..<maximumCount {
            if lhs.indices.contains(index) {
                result.append(lhs[index])
            }
            if rhs.indices.contains(index) {
                result.append(rhs[index])
            }
        }
        return result
    }

    private static func firstRenderedImageURL(for article: ReaderArticleDTO) -> URL? {
        ArticleScreenContentRenderer.renderBody(for: article).blocks.lazy.compactMap { block in
            guard case .image(let url) = block else { return nil }
            return url
        }.first
    }
}

private extension ReaderAdjacentArticleImagePrefetchContext {
    var prefetchScope: ReaderAdjacentArticleImagePrefetchScope {
        ReaderAdjacentArticleImagePrefetchScope(
            articleListSessionID: articleListSessionID,
            displayTarget: displayTarget
        )
    }
}

private struct ReaderAdjacentArticleImagePrefetchScope: Equatable {
    let articleListSessionID: UUID
    let displayTarget: ArticleImageDisplayTarget
}

private struct ActivePrefetchTask {
    let id: UUID
    let task: Task<Void, Never>
}
