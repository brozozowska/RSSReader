import Foundation

nonisolated enum ArticleRetentionTimeRule: Equatable, Sendable {
    case whileReturnedByFeed
    case sourceAge(maximumAge: TimeInterval)
}

nonisolated struct ArticleRetentionContract: Equatable, Sendable {
    static let current = ArticleRetentionContract(
        maximumUnstarredArticleCountPerFeed: 2_000
    )

    let maximumUnstarredArticleCountPerFeed: Int
    let starredArticlesAreExemptFromAutomaticRetention = true

    init(maximumUnstarredArticleCountPerFeed: Int) {
        precondition(maximumUnstarredArticleCountPerFeed > 0)
        self.maximumUnstarredArticleCountPerFeed = maximumUnstarredArticleCountPerFeed
    }

    func timeRule(for policy: ArticleRetentionPolicy) -> ArticleRetentionTimeRule {
        switch policy {
        case .currentFeedOnly:
            .whileReturnedByFeed
        case .twoDays:
            .sourceAge(maximumAge: 2 * 24 * 60 * 60)
        case .oneWeek:
            .sourceAge(maximumAge: 7 * 24 * 60 * 60)
        case .twoWeeks:
            .sourceAge(maximumAge: 14 * 24 * 60 * 60)
        case .oneMonth:
            .sourceAge(maximumAge: 30 * 24 * 60 * 60)
        }
    }

    func sourceAgeReferenceDate(
        publishedAt: Date?,
        updatedAtSource: Date?,
        firstMaterializedAt: Date
    ) -> Date? {
        guard let sourceDate = publishedAt ?? updatedAtSource else {
            return nil
        }

        return min(sourceDate, firstMaterializedAt)
    }

    func countOrderingDate(
        publishedAt: Date?,
        updatedAtSource: Date?,
        firstMaterializedAt: Date
    ) -> Date {
        sourceAgeReferenceDate(
            publishedAt: publishedAt,
            updatedAtSource: updatedAtSource,
            firstMaterializedAt: firstMaterializedAt
        ) ?? firstMaterializedAt
    }

    func sourceAgeCutoffDate(for policy: ArticleRetentionPolicy, now: Date) -> Date? {
        guard case .sourceAge(let maximumAge) = timeRule(for: policy) else {
            return nil
        }

        return now.addingTimeInterval(-maximumAge)
    }
}
