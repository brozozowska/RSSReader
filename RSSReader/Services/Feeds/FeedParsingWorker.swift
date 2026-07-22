import Foundation

nonisolated protocol FeedParsingWorking: Sendable {
    func parse(_ response: FeedResponse) async throws -> FeedParsePipelineResult
}

nonisolated struct FeedParsingWorker: FeedParsingWorking, Sendable {
    typealias Pipeline = @Sendable (FeedResponse) throws -> FeedParsePipelineResult

    private let pipeline: Pipeline

    init(
        pipeline: @escaping Pipeline = { response in
            try FeedParserService.parsePipelineResult(response)
        }
    ) {
        self.pipeline = pipeline
    }

    func parse(_ response: FeedResponse) async throws -> FeedParsePipelineResult {
        try Task.checkCancellation()

        let pipeline = self.pipeline
        let parsingTask = Task.detached(priority: Task.currentPriority) {
            try Task.checkCancellation()
            let result = try pipeline(response)
            try Task.checkCancellation()
            return result
        }

        return try await withTaskCancellationHandler {
            try await parsingTask.value
        } onCancel: {
            parsingTask.cancel()
        }
    }
}
