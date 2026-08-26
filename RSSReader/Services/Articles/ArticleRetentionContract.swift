import Foundation

nonisolated enum ArticleRetentionTimeRule: Equatable, Sendable {
    case removeOnFeedAbsence
    case archivedAge(maximumAge: TimeInterval)
}

nonisolated struct ArticleRetentionContract: Equatable, Sendable {
    static let current = ArticleRetentionContract(
        maximumArchivedUnstarredArticleCountPerFeed: 2_000
    )

    let maximumArchivedUnstarredArticleCountPerFeed: Int
    let starredArticlesAreExemptFromAutomaticRetention = true

    init(maximumArchivedUnstarredArticleCountPerFeed: Int) {
        precondition(maximumArchivedUnstarredArticleCountPerFeed > 0)
        self.maximumArchivedUnstarredArticleCountPerFeed = maximumArchivedUnstarredArticleCountPerFeed
    }

    func timeRule(for policy: ArticleRetentionPolicy) -> ArticleRetentionTimeRule {
        switch policy {
        case .currentFeedOnly:
            .removeOnFeedAbsence
        case .twoDays:
            .archivedAge(maximumAge: 2 * 24 * 60 * 60)
        case .oneWeek:
            .archivedAge(maximumAge: 7 * 24 * 60 * 60)
        case .twoWeeks:
            .archivedAge(maximumAge: 14 * 24 * 60 * 60)
        case .oneMonth:
            .archivedAge(maximumAge: 30 * 24 * 60 * 60)
        }
    }

    func archiveCutoffDate(for policy: ArticleRetentionPolicy, now: Date) -> Date? {
        guard case .archivedAge(let maximumAge) = timeRule(for: policy) else {
            return nil
        }

        return now.addingTimeInterval(-maximumAge)
    }
}
