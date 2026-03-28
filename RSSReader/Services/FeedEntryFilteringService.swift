import Foundation

enum FeedEntryRejectionReason: String, Sendable {
    case missingExternalID
    case missingReadablePayload
    case missingUsefulReference
}

struct RejectedFeedEntryDiagnostic: Sendable {
    let entry: ParsedFeedEntryDTO
    let reasons: [FeedEntryRejectionReason]
}

struct FeedEntryFilterResult: Sendable {
    let validEntries: [ParsedFeedEntryDTO]
    let rejectedEntries: [RejectedFeedEntryDiagnostic]
}

enum FeedEntryFilteringService {
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
        let result = filterEntries(feed.entries)
        return FeedEntryFilterResult(
            validEntries: result.validEntries,
            rejectedEntries: result.rejectedEntries
        )
    }

    static func filterEntries(_ entries: [ParsedFeedEntryDTO]) -> FeedEntryFilterResult {
        var validEntries: [ParsedFeedEntryDTO] = []
        var rejectedEntries: [RejectedFeedEntryDiagnostic] = []

        for entry in entries {
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
        }

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

        if hasValue(entry.externalID) == false {
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
