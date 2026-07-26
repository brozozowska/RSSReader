import Foundation

nonisolated protocol FeedParsingWorking: Sendable {
    func parsePreview(_ response: FeedResponse) async throws -> FeedPreviewParsingResult
    func parseRefresh(
        _ response: FeedResponse,
        fetchedAt: Date
    ) async throws -> FeedRefreshParsingResult
}

extension FeedParsingWorking {
    func parseRefresh(_ response: FeedResponse) async throws -> FeedRefreshParsingResult {
        try await parseRefresh(response, fetchedAt: .now)
    }
}

nonisolated struct FeedPreviewParsingResult: Sendable {
    let pipelineResult: FeedParsePipelineResult

    var feed: ParsedFeedDTO {
        pipelineResult.feed
    }

    var diagnostics: FeedParsePipelineDiagnostics {
        pipelineResult.diagnostics
    }
}

nonisolated struct FeedRefreshParsingResult: Sendable {
    let metadata: ParsedFeedMetadataDTO
    let kind: FeedKind
    let acceptedEntryCount: Int
    let diagnostics: FeedParsePipelineDiagnostics
    let articlePayloads: [ArticleUpsertPayload]
}

nonisolated struct FeedParsingWorker: FeedParsingWorking, Sendable {
    typealias Pipeline = @Sendable (FeedResponse) throws -> FeedParsePipelineResult
    typealias PayloadPreparation = @Sendable ([ParsedFeedEntryDTO], Date) throws -> [ArticleUpsertPayload]

    private let pipeline: Pipeline
    private let payloadPreparation: PayloadPreparation

    init(
        pipeline: @escaping Pipeline = { response in
            try FeedParserService.parsePipelineResult(response)
        },
        payloadPreparation: @escaping PayloadPreparation = { entries, fetchedAt in
            try ArticleUpsertPayload.makeAllPrepared(entries: entries, fetchedAt: fetchedAt)
        }
    ) {
        self.pipeline = pipeline
        self.payloadPreparation = payloadPreparation
    }

    func parsePreview(_ response: FeedResponse) async throws -> FeedPreviewParsingResult {
        try Task.checkCancellation()

        let pipeline = self.pipeline
        return try await runDetached {
            try Task.checkCancellation()
            let pipelineResult = try pipeline(response)
            try Task.checkCancellation()
            return FeedPreviewParsingResult(pipelineResult: pipelineResult)
        }
    }

    func parseRefresh(
        _ response: FeedResponse,
        fetchedAt: Date
    ) async throws -> FeedRefreshParsingResult {
        try Task.checkCancellation()

        let pipeline = self.pipeline
        let payloadPreparation = self.payloadPreparation
        return try await runDetached {
            try Task.checkCancellation()
            let pipelineResult = try pipeline(response)
            try Task.checkCancellation()
            let articlePayloads = try payloadPreparation(pipelineResult.feed.entries, fetchedAt)
            try Task.checkCancellation()
            return FeedRefreshParsingResult(
                metadata: pipelineResult.feed.metadata,
                kind: pipelineResult.feed.kind,
                acceptedEntryCount: pipelineResult.feed.entries.count,
                diagnostics: pipelineResult.diagnostics,
                articlePayloads: articlePayloads
            )
        }
    }

    private func runDetached<Result: Sendable>(
        _ operation: @escaping @Sendable () throws -> Result
    ) async throws -> Result {
        let parsingTask = Task.detached(priority: Task.currentPriority, operation: operation)
        return try await withTaskCancellationHandler {
            try await parsingTask.value
        } onCancel: {
            parsingTask.cancel()
        }
    }
}
