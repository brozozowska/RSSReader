import Foundation
import Observation

enum FeedRefreshOperation: Hashable, Sendable {
    case selection(ManualFeedRefreshScope)
    case failedFeeds(ManualFeedRefreshScope)
    case background
}

struct FeedIssue: Equatable, Identifiable, Sendable {
    enum Target: Hashable, Sendable {
        case feed(UUID)
        case operation(FeedRefreshOperation)
    }

    let id: Target
    let reason: FeedRefreshFailureReason
    let attemptedAt: Date
    let canRetry: Bool

    var retryAt: Date? {
        guard case .httpStatus(_, let retryAt) = reason else { return nil }
        return retryAt
    }
}

@MainActor
@Observable
final class FeedIssueState {
    private(set) var issues: [FeedIssue.Target: FeedIssue] = [:]
    @ObservationIgnored private var attempts: [FeedIssue.Target: UUID] = [:]
    @ObservationIgnored private var failedFeedRetryTargets: [FeedRefreshOperation: [UUID]] = [:]

    func begin(_ target: FeedIssue.Target) -> UUID {
        let token = UUID()
        attempts[target] = token
        return token
    }

    func finish(
        _ target: FeedIssue.Target,
        token: UUID,
        attemptedAt: Date,
        reason: FeedRefreshFailureReason?,
        cancelled: Bool = false,
        retryAvailable: Bool = true,
        retryFeedIDs: [UUID] = []
    ) {
        guard attempts[target] == token else { return }
        attempts.removeValue(forKey: target)
        guard !cancelled else { return }

        if let reason {
            let canRetry: Bool
            if case .operation(.failedFeeds) = target {
                canRetry = retryAvailable && !retryFeedIDs.isEmpty
            } else {
                canRetry = retryAvailable
            }
            issues[target] = FeedIssue(id: target, reason: reason, attemptedAt: attemptedAt, canRetry: canRetry)
        } else if issues[target] != nil {
            issues.removeValue(forKey: target)
        }
        if case .operation(let operation) = target {
            failedFeedRetryTargets[operation] = reason == nil || retryFeedIDs.isEmpty ? nil : retryFeedIDs
        }
    }

    func retryFeedIDs(for operation: FeedRefreshOperation) -> [UUID]? {
        failedFeedRetryTargets[operation]
    }

    func removeFeed(_ feedID: UUID) {
        let retryOperation = FeedRefreshOperation.failedFeeds(.feed(feedID))
        failedFeedRetryTargets.removeValue(forKey: retryOperation)
        let targets: [FeedIssue.Target] = [.feed(feedID), .operation(.selection(.feed(feedID))), .operation(retryOperation)]
        for target in targets {
            attempts.removeValue(forKey: target)
            if issues[target] != nil {
                issues.removeValue(forKey: target)
            }
        }
    }
}
