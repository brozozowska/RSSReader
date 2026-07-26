import Foundation

nonisolated enum FeedEntryRejectionReason: String, Sendable {
    case missingExternalID
    case missingReadablePayload
    case missingUsefulReference
}

nonisolated struct RejectedFeedEntryDiagnostic: Sendable {
    let entry: ParsedFeedEntryDTO
    let reasons: [FeedEntryRejectionReason]
}

nonisolated struct FeedEntryFilterResult: Sendable {
    let validEntries: [ParsedFeedEntryDTO]
    let rejectedEntries: [RejectedFeedEntryDiagnostic]
}

nonisolated enum FeedEntryFilteringService {
    static func filterValidEntries(from feed: ParsedFeedDTO) -> ParsedFeedDTO {
        ParsedFeedDTO(
            kind: feed.kind,
            metadata: feed.metadata,
            entries: filterEntries(feed.entries).validEntries
        )
    }

    static func filterValidEntries(_ entries: [ParsedFeedEntryDTO]) -> [ParsedFeedEntryDTO] {
        filterEntries(entries).validEntries
    }

    static func filterEntries(from feed: ParsedFeedDTO) -> FeedEntryFilterResult {
        filterEntries(
            from: feed,
            cancellationCheck: {},
            progressProbe: nil
        )
    }

    static func filterEntries(
        from feed: ParsedFeedDTO,
        cancellationCheck: FeedParsingCancellationCheck,
        progressProbe: FeedEntryLoopProgressProbe?
    ) rethrows -> FeedEntryFilterResult {
        let result = try filterEntries(
            feed.entries,
            cancellationCheck: cancellationCheck,
            progressProbe: progressProbe
        )
        return FeedEntryFilterResult(
            validEntries: result.validEntries,
            rejectedEntries: result.rejectedEntries
        )
    }

    static func filterEntries(_ entries: [ParsedFeedEntryDTO]) -> FeedEntryFilterResult {
        filterEntries(
            entries,
            cancellationCheck: {},
            progressProbe: nil
        )
    }

    static func filterEntries(
        _ entries: [ParsedFeedEntryDTO],
        cancellationCheck: FeedParsingCancellationCheck,
        progressProbe: FeedEntryLoopProgressProbe?
    ) rethrows -> FeedEntryFilterResult {
        var validEntries: [ParsedFeedEntryDTO] = []
        var rejectedEntries: [RejectedFeedEntryDiagnostic] = []

        for (index, entry) in entries.enumerated() {
            try FeedParsingCancellationPolicy.checkBeforeEntry(
                at: index,
                cancellationCheck: cancellationCheck
            )
            let reasons = rejectionReasons(for: entry)
            if reasons.isEmpty {
                validEntries.append(entry)
            } else {
                rejectedEntries.append(
                    RejectedFeedEntryDiagnostic(
                        entry: entry,
                        reasons: reasons
                    )
                )
            }
            progressProbe?(index + 1)
        }
        try cancellationCheck()

        return FeedEntryFilterResult(
            validEntries: validEntries,
            rejectedEntries: rejectedEntries
        )
    }

    static func isValid(_ entry: ParsedFeedEntryDTO) -> Bool {
        rejectionReasons(for: entry).isEmpty
    }

    static func rejectionReasons(for entry: ParsedFeedEntryDTO) -> [FeedEntryRejectionReason] {
        var reasons: [FeedEntryRejectionReason] = []

        if ArticleUpsertPayload.hasPersistableExternalID(entry) == false {
            reasons.append(.missingExternalID)
        }

        let hasReadablePayload =
            hasValue(entry.title) ||
            hasValue(entry.summary) ||
            hasValue(entry.contentHTML) ||
            hasValue(entry.contentText)
        if hasReadablePayload == false {
            reasons.append(.missingReadablePayload)
        }

        let hasUsefulReference =
            hasValue(entry.guid) ||
            isLikelyURL(entry.url) ||
            isLikelyURL(entry.canonicalURL)
        if hasUsefulReference == false {
            reasons.append(.missingUsefulReference)
        }

        return reasons
    }

    private static func hasValue(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }

    private static func isLikelyURL(_ value: String?) -> Bool {
        guard let value, hasValue(value) else { return false }
        guard let components = URLComponents(string: value) else { return false }
        guard let scheme = components.scheme?.lowercased(), let host = components.host else {
            return false
        }

        let isSupportedScheme = scheme == "http" || scheme == "https"
        return isSupportedScheme && host.isEmpty == false
    }
}
