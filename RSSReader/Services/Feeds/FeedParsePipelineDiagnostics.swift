import Foundation

nonisolated enum FeedParserAnomalyKind: Sendable {
    case missingFeedTitle
    case missingFeedSiteURL
    case entryMissingTitle
    case entryMissingURL
    case entryMissingDates
    case entryMissingContent
}

nonisolated struct FeedParserAnomaly: Sendable {
    let kind: FeedParserAnomalyKind
    let entryIndex: Int?
    let message: String
}

nonisolated struct FeedParsePipelineDiagnostics: Sendable {
    let parserAnomalies: [FeedParserAnomaly]
    let rejectedEntries: [RejectedFeedEntryDiagnostic]

    var hasIssues: Bool {
        parserAnomalies.isEmpty == false || rejectedEntries.isEmpty == false
    }
}

nonisolated struct FeedParsePipelineResult: Sendable {
    let feed: ParsedFeedDTO
    let diagnostics: FeedParsePipelineDiagnostics
}

extension FeedParserService {
    nonisolated static func parsePipeline(_ response: FeedResponse) throws -> ParsedFeedDTO {
        try parsePipelineResult(response).feed
    }

    nonisolated static func parsePipeline(_ data: Data, feedURL: String) throws -> ParsedFeedDTO {
        try parsePipelineResult(data, feedURL: feedURL).feed
    }

    nonisolated static func parsePipeline(_ parsedFeed: ParsedFeedDTO, feedURL: String) -> ParsedFeedDTO {
        parsePipelineResult(parsedFeed, feedURL: feedURL).feed
    }

    nonisolated static func parsePipelineResult(
        _ response: FeedResponse,
        xmlCancellationProbe: @escaping FeedXMLParserCancellationProbe = { Task.isCancelled },
        xmlProgressProbe: FeedXMLParserProgressProbe? = nil
    ) throws -> FeedParsePipelineResult {
        let document = try parse(
            response,
            cancellationProbe: xmlCancellationProbe,
            progressProbe: xmlProgressProbe
        )
        try Task.checkCancellation()
        let parsedFeed = try parseFeed(document)
        try Task.checkCancellation()
        return try makePipelineResult(
            parsedFeed,
            feedURL: response.request.url.absoluteString,
            cancellationCheck: { try Task.checkCancellation() }
        )
    }

    nonisolated static func parsePipelineResult(
        _ data: Data,
        feedURL: String,
        xmlCancellationProbe: @escaping FeedXMLParserCancellationProbe = { Task.isCancelled },
        xmlProgressProbe: FeedXMLParserProgressProbe? = nil
    ) throws -> FeedParsePipelineResult {
        let document = try parse(
            data,
            cancellationProbe: xmlCancellationProbe,
            progressProbe: xmlProgressProbe
        )
        try Task.checkCancellation()
        let parsedFeed = try parseFeed(document)
        try Task.checkCancellation()
        return try makePipelineResult(
            parsedFeed,
            feedURL: feedURL,
            cancellationCheck: { try Task.checkCancellation() }
        )
    }

    nonisolated static func parsePipelineResult(
        _ parsedFeed: ParsedFeedDTO,
        feedURL: String
    ) -> FeedParsePipelineResult {
        makePipelineResult(
            parsedFeed,
            feedURL: feedURL,
            cancellationCheck: {}
        )
    }

    nonisolated private static func makePipelineResult(
        _ parsedFeed: ParsedFeedDTO,
        feedURL: String,
        cancellationCheck: () throws -> Void
    ) rethrows -> FeedParsePipelineResult {
        let normalizedFeed = FeedNormalizationService.normalize(parsedFeed, feedURL: feedURL)
        try cancellationCheck()
        let parserAnomalies = collectParserAnomalies(in: normalizedFeed)
        try cancellationCheck()
        let deduplicatedFeed = DeduplicationService.deduplicate(normalizedFeed)
        try cancellationCheck()
        let filteringResult = FeedEntryFilteringService.filterEntries(from: deduplicatedFeed)
        try cancellationCheck()
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

    nonisolated private static func collectParserAnomalies(in feed: ParsedFeedDTO) -> [FeedParserAnomaly] {
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

    nonisolated private static func hasValue(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}
