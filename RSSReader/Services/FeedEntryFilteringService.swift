import Foundation

enum FeedEntryFilteringService {
    static func filterValidEntries(from feed: ParsedFeedDTO) -> ParsedFeedDTO {
        ParsedFeedDTO(
            kind: feed.kind,
            metadata: feed.metadata,
            entries: filterValidEntries(feed.entries)
        )
    }

    static func filterValidEntries(_ entries: [ParsedFeedEntryDTO]) -> [ParsedFeedEntryDTO] {
        entries.filter { isValid($0) }
    }

    static func isValid(_ entry: ParsedFeedEntryDTO) -> Bool {
        let hasStableIdentity = hasValue(entry.externalID)
        let hasReadablePayload =
            hasValue(entry.title) ||
            hasValue(entry.summary) ||
            hasValue(entry.contentHTML) ||
            hasValue(entry.contentText)
        let hasUsefulReference =
            hasValue(entry.guid) ||
            isLikelyURL(entry.url) ||
            isLikelyURL(entry.canonicalURL)

        return hasStableIdentity && (hasReadablePayload || hasUsefulReference)
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
