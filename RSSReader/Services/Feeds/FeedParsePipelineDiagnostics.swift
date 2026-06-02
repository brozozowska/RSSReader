import Foundation

enum FeedParserAnomalyKind: Sendable {
    case missingFeedTitle
    case missingFeedSiteURL
    case entryMissingTitle
    case entryMissingURL
    case entryMissingDates
    case entryMissingContent
}

struct FeedParserAnomaly: Sendable {
    let kind: FeedParserAnomalyKind
    let entryIndex: Int?
    let message: String
}

struct FeedParsePipelineDiagnostics: Sendable {
    let parserAnomalies: [FeedParserAnomaly]
    let rejectedEntries: [RejectedFeedEntryDiagnostic]

    var hasIssues: Bool {
        parserAnomalies.isEmpty == false || rejectedEntries.isEmpty == false
    }
}

struct FeedParsePipelineResult: Sendable {
    let feed: ParsedFeedDTO
    let diagnostics: FeedParsePipelineDiagnostics
}

extension FeedParserService {
    static func parsePipeline(_ response: FeedResponse) throws -> ParsedFeedDTO {
        try parsePipelineResult(response).feed
    }

    static func parsePipeline(_ data: Data, feedURL: String) throws -> ParsedFeedDTO {
        try parsePipelineResult(data, feedURL: feedURL).feed
    }

    static func parsePipeline(_ parsedFeed: ParsedFeedDTO, feedURL: String) -> ParsedFeedDTO {
        parsePipelineResult(parsedFeed, feedURL: feedURL).feed
    }

    static func parsePipelineResult(_ response: FeedResponse) throws -> FeedParsePipelineResult {
        let parsedFeed = try parseFeed(response)
        return parsePipelineResult(parsedFeed, feedURL: response.request.url.absoluteString)
    }

    static func parsePipelineResult(_ data: Data, feedURL: String) throws -> FeedParsePipelineResult {
        let parsedFeed = try parseFeed(parse(data))
        return parsePipelineResult(parsedFeed, feedURL: feedURL)
    }

    static func parsePipelineResult(_ parsedFeed: ParsedFeedDTO, feedURL: String) -> FeedParsePipelineResult {
        let normalizedFeed = FeedNormalizationService.normalize(parsedFeed, feedURL: feedURL)
        let parserAnomalies = collectParserAnomalies(in: normalizedFeed)
        let deduplicatedFeed = DeduplicationService.deduplicate(normalizedFeed)
        let filteringResult = FeedEntryFilteringService.filterEntries(from: deduplicatedFeed)
        let filteredFeed = ParsedFeedDTO(
            kind: deduplicatedFeed.kind,
            metadata: deduplicatedFeed.metadata,
            entries: filteringResult.validEntries
        )

        return FeedParsePipelineResult(
            feed: filteredFeed,
            diagnostics: FeedParsePipelineDiagnostics(
                parserAnomalies: parserAnomalies,
                rejectedEntries: filteringResult.rejectedEntries
            )
        )
    }

    private static func collectParserAnomalies(in feed: ParsedFeedDTO) -> [FeedParserAnomaly] {
        var anomalies: [FeedParserAnomaly] = []

        if hasValue(feed.metadata.title) == false {
            anomalies.append(
                FeedParserAnomaly(
                    kind: .missingFeedTitle,
                    entryIndex: nil,
                    message: "Feed metadata is missing title"
                )
            )
        }

        if hasValue(feed.metadata.siteURL) == false {
            anomalies.append(
                FeedParserAnomaly(
                    kind: .missingFeedSiteURL,
                    entryIndex: nil,
                    message: "Feed metadata is missing site URL"
                )
            )
        }

        for (index, entry) in feed.entries.enumerated() {
            if hasValue(entry.title) == false {
                anomalies.append(
                    FeedParserAnomaly(
                        kind: .entryMissingTitle,
                        entryIndex: index,
                        message: "Entry is missing title"
                    )
                )
            }

            if hasValue(entry.url) == false && hasValue(entry.canonicalURL) == false {
                anomalies.append(
                    FeedParserAnomaly(
                        kind: .entryMissingURL,
                        entryIndex: index,
                        message: "Entry is missing both article URL and canonical URL"
                    )
                )
            }

            if hasValue(entry.publishedAtRaw) == false && hasValue(entry.updatedAtRaw) == false {
                anomalies.append(
                    FeedParserAnomaly(
                        kind: .entryMissingDates,
                        entryIndex: index,
                        message: "Entry is missing published and updated dates"
                    )
                )
            }

            if hasValue(entry.summary) == false &&
                hasValue(entry.contentHTML) == false &&
                hasValue(entry.contentText) == false {
                anomalies.append(
                    FeedParserAnomaly(
                        kind: .entryMissingContent,
                        entryIndex: index,
                        message: "Entry is missing summary and content payload"
                    )
                )
            }
        }

        return anomalies
    }

    private static func hasValue(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}
