import Foundation

nonisolated enum FeedParsingEntryStage: CaseIterable, Hashable, Sendable {
    case normalization
    case diagnostics
    case deduplication
    case filtering
}

typealias FeedParsingCancellationCheck = @Sendable () throws -> Void
typealias FeedParsingEntryProgressProbe = @Sendable (FeedParsingEntryStage, Int) -> Void
typealias FeedEntryLoopProgressProbe = @Sendable (Int) -> Void

nonisolated enum FeedParsingCancellationPolicy {
    static let entryCheckpointInterval = 32

    static func checkBeforeEntry(
        at index: Int,
        cancellationCheck: FeedParsingCancellationCheck
    ) rethrows {
        if index.isMultiple(of: entryCheckpointInterval) {
            try cancellationCheck()
        }
    }
}
