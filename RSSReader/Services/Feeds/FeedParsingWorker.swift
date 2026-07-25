import Foundation

nonisolated protocol FeedParsingWorking: Sendable {
    func parse(_ response: FeedResponse, fetchedAt: Date) async throws -> FeedParsingWorkerResult
}

extension FeedParsingWorking {
    func parse(_ response: FeedResponse) async throws -> FeedParsingWorkerResult {
        try await parse(response, fetchedAt: .now)
    }
}

nonisolated struct FeedParsingWorkerResult: Sendable {
    let pipelineResult: FeedParsePipelineResult
    let articlePayloads: [ArticleUpsertPayload]

    var feed: ParsedFeedDTO {
        pipelineResult.feed
    }

    var diagnostics: FeedParsePipelineDiagnostics {
        pipelineResult.diagnostics
    }
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

    func parse(_ response: FeedResponse, fetchedAt: Date) async throws -> FeedParsingWorkerResult {
        try Task.checkCancellation()

        let pipeline = self.pipeline
        let payloadPreparation = self.payloadPreparation
        let parsingTask = Task.detached(priority: Task.currentPriority) {
            try Task.checkCancellation()
            let pipelineResult = try pipeline(response)
            try Task.checkCancellation()
            let articlePayloads = try payloadPreparation(pipelineResult.feed.entries, fetchedAt)
            try Task.checkCancellation()
            return FeedParsingWorkerResult(
                pipelineResult: pipelineResult,
                articlePayloads: articlePayloads
            )
        }

        return try await withTaskCancellationHandler {
            try await parsingTask.value
        } onCancel: {
            parsingTask.cancel()
        }
    }
}
