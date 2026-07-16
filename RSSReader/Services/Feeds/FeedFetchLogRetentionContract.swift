import Foundation

nonisolated struct FeedFetchLogRetentionContract: Equatable, Sendable {
    static let current = FeedFetchLogRetentionContract(
        maximumAge: 7 * 24 * 60 * 60,
        maximumLogCountPerFeed: 200
    )

    let maximumAge: TimeInterval
    let maximumLogCountPerFeed: Int

    init(
        maximumAge: TimeInterval,
        maximumLogCountPerFeed: Int
    ) {
        precondition(maximumAge > 0)
        precondition(maximumLogCountPerFeed > 0)
        self.maximumAge = maximumAge
        self.maximumLogCountPerFeed = maximumLogCountPerFeed
    }

    func cutoffDate(now: Date) -> Date {
        now.addingTimeInterval(-maximumAge)
    }
}
