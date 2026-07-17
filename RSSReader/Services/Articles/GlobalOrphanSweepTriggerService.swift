import Foundation

struct GlobalOrphanSweepTriggerContract: Equatable, Sendable {
    nonisolated static let current = GlobalOrphanSweepTriggerContract(
        successfulSweepCadence: 7 * 24 * 60 * 60,
        feedScopedCleanupSuppressionWindow: 60 * 60
    )

    let successfulSweepCadence: TimeInterval
    let feedScopedCleanupSuppressionWindow: TimeInterval

    init(
        successfulSweepCadence: TimeInterval,
        feedScopedCleanupSuppressionWindow: TimeInterval
    ) {
        precondition(successfulSweepCadence > 0)
        precondition(feedScopedCleanupSuppressionWindow >= 0)
        self.successfulSweepCadence = successfulSweepCadence
        self.feedScopedCleanupSuppressionWindow = feedScopedCleanupSuppressionWindow
    }

    func decision(
        for snapshot: GlobalOrphanSweepScheduleSnapshot,
        now: Date
    ) -> GlobalOrphanSweepTriggerDecision {
        if let lastSuccessfulSweepAt = snapshot.lastSuccessfulSweepAt {
            let nextCadenceDate = lastSuccessfulSweepAt.addingTimeInterval(successfulSweepCadence)
            if now < nextCadenceDate {
                return .suppressed(.cadence(nextEligibleAt: nextCadenceDate))
            }
        }

        if let lastFeedScopedRetentionCleanupAt = snapshot.lastFeedScopedRetentionCleanupAt {
            let nextEligibleDate = lastFeedScopedRetentionCleanupAt.addingTimeInterval(
                feedScopedCleanupSuppressionWindow
            )
            if now < nextEligibleDate {
                return .suppressed(.recentFeedScopedRetentionCleanup(nextEligibleAt: nextEligibleDate))
            }
        }

        return .run
    }
}

struct GlobalOrphanSweepScheduleSnapshot: Equatable, Sendable {
    let lastSuccessfulSweepAt: Date?
    let lastFeedScopedRetentionCleanupAt: Date?
}

enum GlobalOrphanSweepSuppressionReason: Equatable, Sendable {
    case cadence(nextEligibleAt: Date)
    case recentFeedScopedRetentionCleanup(nextEligibleAt: Date)
    case alreadyRunning
}

enum GlobalOrphanSweepTriggerDecision: Equatable, Sendable {
    case run
    case suppressed(GlobalOrphanSweepSuppressionReason)
}

enum GlobalOrphanSweepTriggerResult: Equatable, Sendable {
    case executed(PersistenceBoundedGrowthCleanupResult)
    case suppressed(GlobalOrphanSweepSuppressionReason)
    case cancelled
    case failed
}

@MainActor
protocol GlobalOrphanSweepScheduleStoring: AnyObject {
    func loadSnapshot() -> GlobalOrphanSweepScheduleSnapshot
    func recordSuccessfulSweep(at date: Date)
    func recordFeedScopedRetentionCleanup(at date: Date)
}

@MainActor
final class InMemoryGlobalOrphanSweepScheduleStore: GlobalOrphanSweepScheduleStoring {
    private var lastSuccessfulSweepAt: Date?
    private var lastFeedScopedRetentionCleanupAt: Date?

    init(
        lastSuccessfulSweepAt: Date? = nil,
        lastFeedScopedRetentionCleanupAt: Date? = nil
    ) {
        self.lastSuccessfulSweepAt = lastSuccessfulSweepAt
        self.lastFeedScopedRetentionCleanupAt = lastFeedScopedRetentionCleanupAt
    }

    func loadSnapshot() -> GlobalOrphanSweepScheduleSnapshot {
        GlobalOrphanSweepScheduleSnapshot(
            lastSuccessfulSweepAt: lastSuccessfulSweepAt,
            lastFeedScopedRetentionCleanupAt: lastFeedScopedRetentionCleanupAt
        )
    }

    func recordSuccessfulSweep(at date: Date) {
        lastSuccessfulSweepAt = latest(lastSuccessfulSweepAt, date)
    }

    func recordFeedScopedRetentionCleanup(at date: Date) {
        lastFeedScopedRetentionCleanupAt = latest(lastFeedScopedRetentionCleanupAt, date)
    }

    private func latest(_ current: Date?, _ candidate: Date) -> Date {
        guard let current else { return candidate }
        return max(current, candidate)
    }
}

@MainActor
final class UserDefaultsGlobalOrphanSweepScheduleStore: GlobalOrphanSweepScheduleStoring {
    private enum Key {
        static let lastSuccessfulSweepAt = "persistence.globalOrphanSweep.lastSuccessfulSweepAt"
        static let lastFeedScopedRetentionCleanupAt =
            "persistence.globalOrphanSweep.lastFeedScopedRetentionCleanupAt"
    }

    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func loadSnapshot() -> GlobalOrphanSweepScheduleSnapshot {
        GlobalOrphanSweepScheduleSnapshot(
            lastSuccessfulSweepAt: date(forKey: Key.lastSuccessfulSweepAt),
            lastFeedScopedRetentionCleanupAt: date(forKey: Key.lastFeedScopedRetentionCleanupAt)
        )
    }

    func recordSuccessfulSweep(at date: Date) {
        recordLatest(date, forKey: Key.lastSuccessfulSweepAt)
    }

    func recordFeedScopedRetentionCleanup(at date: Date) {
        recordLatest(date, forKey: Key.lastFeedScopedRetentionCleanupAt)
    }

    private func date(forKey key: String) -> Date? {
        guard userDefaults.object(forKey: key) != nil else { return nil }
        return Date(timeIntervalSince1970: userDefaults.double(forKey: key))
    }

    private func recordLatest(_ date: Date, forKey key: String) {
        if let current = self.date(forKey: key), date <= current {
            return
        }
        userDefaults.set(date.timeIntervalSince1970, forKey: key)
    }
}

@MainActor
protocol GlobalOrphanSweepTriggerServicing: AnyObject {
    func recordFeedScopedRetentionCleanupCompleted(at date: Date)
    func recordSuccessfulGlobalSweepCompleted(at date: Date)

    @discardableResult
    func runIfDue(now: Date) async -> GlobalOrphanSweepTriggerResult
}

@MainActor
final class GlobalOrphanSweepTriggerService: GlobalOrphanSweepTriggerServicing {
    private let logger: Logging
    private let cleanupService: any PersistenceBoundedGrowthCleanupServicing
    private let scheduleStore: any GlobalOrphanSweepScheduleStoring
    private let contract: GlobalOrphanSweepTriggerContract
    private var isRunning = false

    init(
        logger: Logging,
        cleanupService: any PersistenceBoundedGrowthCleanupServicing,
        scheduleStore: any GlobalOrphanSweepScheduleStoring,
        contract: GlobalOrphanSweepTriggerContract = .current
    ) {
        self.logger = logger
        self.cleanupService = cleanupService
        self.scheduleStore = scheduleStore
        self.contract = contract
    }

    func recordFeedScopedRetentionCleanupCompleted(at date: Date) {
        let snapshot = scheduleStore.loadSnapshot()
        guard let lastSuccessfulSweepAt = snapshot.lastSuccessfulSweepAt else {
            if snapshot.lastFeedScopedRetentionCleanupAt == nil {
                scheduleStore.recordFeedScopedRetentionCleanup(at: date)
            }
            return
        }

        let cadenceDueAt = lastSuccessfulSweepAt.addingTimeInterval(
            contract.successfulSweepCadence
        )
        if date < cadenceDueAt {
            scheduleStore.recordFeedScopedRetentionCleanup(at: date)
            return
        }

        if let suppressionAnchor = snapshot.lastFeedScopedRetentionCleanupAt,
           suppressionAnchor >= cadenceDueAt {
            return
        }
        scheduleStore.recordFeedScopedRetentionCleanup(at: date)
    }

    func recordSuccessfulGlobalSweepCompleted(at date: Date) {
        scheduleStore.recordSuccessfulSweep(at: date)
    }

    @discardableResult
    func runIfDue(now: Date = .now) async -> GlobalOrphanSweepTriggerResult {
        guard isRunning == false else {
            logger.debug("Global orphan sweep skipped reason=alreadyRunning")
            return .suppressed(.alreadyRunning)
        }

        let decision = contract.decision(for: scheduleStore.loadSnapshot(), now: now)
        if case .suppressed(let reason) = decision {
            logger.debug("Global orphan sweep skipped reason=\(reason.logDescription)")
            return .suppressed(reason)
        }

        isRunning = true
        defer { isRunning = false }

        do {
            try Task.checkCancellation()
            await Task.yield()
            try Task.checkCancellation()
            let result = try cleanupService.cleanupBoundedGrowth(now: now)
            scheduleStore.recordSuccessfulSweep(at: now)
            logger.info(
                "Global orphan sweep lifecycle trigger completed deletedArticleStates=\(result.deletedArticleStateCount) deletedFeedFetchLogs=\(result.deletedFeedFetchLogCount)"
            )
            return .executed(result)
        } catch is CancellationError {
            logger.debug("Global orphan sweep lifecycle trigger cancelled")
            return .cancelled
        } catch {
            logger.error("Global orphan sweep lifecycle trigger failed: \(error)")
            return .failed
        }
    }
}

private extension GlobalOrphanSweepSuppressionReason {
    var logDescription: String {
        switch self {
        case .cadence(let nextEligibleAt):
            "cadence nextEligibleAt=\(nextEligibleAt.timeIntervalSince1970)"
        case .recentFeedScopedRetentionCleanup(let nextEligibleAt):
            "recentFeedScopedRetentionCleanup nextEligibleAt=\(nextEligibleAt.timeIntervalSince1970)"
        case .alreadyRunning:
            "alreadyRunning"
        }
    }
}
