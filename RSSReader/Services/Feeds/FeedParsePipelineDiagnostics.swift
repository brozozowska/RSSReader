import Foundation

nonisolated enum FeedParserAnomalyKind: Sendable {
    case missingFeedTitle
    case missingFeedSiteURL
    case entryMissingTitle
    case entryMissingURL
    case entryMissingDates
    case entryUnrecognizedPublishedDate
    case entryUnrecognizedUpdatedDate
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
        xmlProgressProbe: FeedXMLParserProgressProbe? = nil,
        entryProgressProbe: FeedParsingEntryProgressProbe? = nil
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
            cancellationCheck: { try Task.checkCancellation() },
            entryProgressProbe: entryProgressProbe
        )
    }

    nonisolated static func parsePipelineResult(
        _ data: Data,
        feedURL: String,
        xmlCancellationProbe: @escaping FeedXMLParserCancellationProbe = { Task.isCancelled },
        xmlProgressProbe: FeedXMLParserProgressProbe? = nil,
        entryProgressProbe: FeedParsingEntryProgressProbe? = nil
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
            cancellationCheck: { try Task.checkCancellation() },
            entryProgressProbe: entryProgressProbe
        )
    }

    nonisolated static func parsePipelineResult(
        _ parsedFeed: ParsedFeedDTO,
        feedURL: String
    ) -> FeedParsePipelineResult {
        makePipelineResult(
            parsedFeed,
            feedURL: feedURL,
            cancellationCheck: {},
            entryProgressProbe: nil
        )
    }

    nonisolated private static func makePipelineResult(
        _ parsedFeed: ParsedFeedDTO,
        feedURL: String,
        cancellationCheck: FeedParsingCancellationCheck,
        entryProgressProbe: FeedParsingEntryProgressProbe?
    ) rethrows -> FeedParsePipelineResult {
        let normalizedFeed = try FeedNormalizationService.normalize(
            parsedFeed,
            feedURL: feedURL,
            cancellationCheck: cancellationCheck,
            progressProbe: makeProgressProbe(
                for: .normalization,
                forwarding: entryProgressProbe
            )
        )
        try cancellationCheck()
        let parserAnomalies = try collectParserAnomalies(
            in: normalizedFeed,
            cancellationCheck: cancellationCheck,
            progressProbe: makeProgressProbe(
                for: .diagnostics,
                forwarding: entryProgressProbe
            )
        )
        try cancellationCheck()
        let deduplicatedFeed = try DeduplicationService.deduplicate(
            normalizedFeed,
            cancellationCheck: cancellationCheck,
            progressProbe: makeProgressProbe(
                for: .deduplication,
                forwarding: entryProgressProbe
            )
        )
        try cancellationCheck()
        let filteringResult = try FeedEntryFilteringService.filterEntries(
            from: deduplicatedFeed,
            cancellationCheck: cancellationCheck,
            progressProbe: makeProgressProbe(
                for: .filtering,
                forwarding: entryProgressProbe
            )
        )
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

    nonisolated private static func collectParserAnomalies(
        in feed: ParsedFeedDTO,
        cancellationCheck: FeedParsingCancellationCheck,
        progressProbe: FeedEntryLoopProgressProbe?
    ) rethrows -> [FeedParserAnomaly] {
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
            try FeedParsingCancellationPolicy.checkBeforeEntry(
                at: index,
                cancellationCheck: cancellationCheck
            )
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

            if hasValue(entry.publishedAtRaw), entry.publishedAt == nil {
                anomalies.append(
                    FeedParserAnomaly(
                        kind: .entryUnrecognizedPublishedDate,
                        entryIndex: index,
                        message: "Entry has an unrecognized published date"
                    )
                )
            }

            if hasValue(entry.updatedAtRaw), entry.updatedAt == nil {
                anomalies.append(
                    FeedParserAnomaly(
                        kind: .entryUnrecognizedUpdatedDate,
                        entryIndex: index,
                        message: "Entry has an unrecognized updated date"
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
            progressProbe?(index + 1)
        }
        try cancellationCheck()

        return anomalies
    }

    nonisolated private static func makeProgressProbe(
        for stage: FeedParsingEntryStage,
        forwarding progressProbe: FeedParsingEntryProgressProbe?
    ) -> FeedEntryLoopProgressProbe? {
        guard let progressProbe else { return nil }
        return { completedEntryCount in
            progressProbe(stage, completedEntryCount)
        }
    }

    nonisolated private static func hasValue(_ value: String?) -> Bool {
        guard let value else { return false }
        return value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
    }
}
