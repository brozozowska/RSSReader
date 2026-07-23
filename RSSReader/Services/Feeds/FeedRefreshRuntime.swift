import Foundation

extension FeedRefreshService {
    func refresh(feedID: UUID) async -> FeedRefreshResult {
        switch inFlightPolicy {
        case .shareExistingTaskResult:
            if let inFlightTask = inFlightRefreshTasks[feedID] {
                logger.info("Joining in-flight refresh for feed \(feedID.uuidString)")
                return await inFlightTask.value
            }

            let task = Task<FeedRefreshResult, Never> { @MainActor [weak self, feedID] in
                guard let self else {
                    return FeedRefreshResult.failed(
                        feedID: feedID,
                        startedAt: Date(),
                        errorDescription: "FeedRefreshService deallocated"
                    )
                }

                defer {
                    self.inFlightRefreshTasks.removeValue(forKey: feedID)
                }
                return await self.performRefresh(feedID: feedID)
            }

            inFlightRefreshTasks[feedID] = task
            return await awaitOwnedInFlightRefreshTask(task)
        }
    }

    private func awaitOwnedInFlightRefreshTask(
        _ task: Task<FeedRefreshResult, Never>
    ) async -> FeedRefreshResult {
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    func performRefresh(feedID: UUID) async -> FeedRefreshResult {
        let startedAt = Date()

        do {
            let context = try makeRefreshContext(for: feedID)
            try markRefreshAttemptStarted(for: context.metadata.id, startedAt: startedAt)
            let fetchResult = try await feedFetcher.fetch(context.request)
            try Task.checkCancellation()

            switch fetchResult {
            case .notModified(let response):
                let result = try await handleNotModifiedResponse(
                    response,
                    metadata: context.metadata,
                    startedAt: startedAt
                )
                persistRefreshLog(
                    feedID: context.metadata.id,
                    status: result.status,
                    httpCode: response.statusCode,
                    diagnosticsSummary: result.diagnosticsSummary,
                    errorDescription: result.errorDescription,
                    finishedAt: result.finishedAt,
                    baseMessage: "Feed not modified"
                )
                return result
            case .fetched(let response):
                let result = try await handleFetchedResponse(
                    response,
                    metadata: context.metadata,
                    startedAt: startedAt
                )
                persistRefreshLog(
                    feedID: context.metadata.id,
                    status: result.status,
                    httpCode: response.statusCode,
                    diagnosticsSummary: result.diagnosticsSummary,
                    errorDescription: result.errorDescription,
                    finishedAt: result.finishedAt
                )
                return result
            }
        } catch is CancellationError {
            feedRepository.rollback()
            logger.info("Cancelled refresh for feed \(feedID.uuidString)")
            let result = makeCancelledResult(feedID: feedID, startedAt: startedAt)
            persistRefreshLog(
                feedID: feedID,
                status: result.status,
                httpCode: nil,
                diagnosticsSummary: result.diagnosticsSummary,
                errorDescription: result.errorDescription,
                finishedAt: result.finishedAt,
                baseMessage: "Refresh cancelled"
            )
            return result
        } catch {
            let finishedAt = Date()
            let errorDescription = String(describing: error)
            feedRepository.rollback()
            try? markRefreshFailed(feedID: feedID, finishedAt: finishedAt, errorDescription: errorDescription)
            persistRefreshLog(
                feedID: feedID,
                status: .failed,
                httpCode: httpCode(from: error),
                diagnosticsSummary: FeedRefreshDiagnosticsSummary(),
                errorDescription: errorDescription,
                finishedAt: finishedAt
            )
            logger.error("Failed to refresh feed \(feedID.uuidString): \(error)")
            return makeFailureResult(
                feedID: feedID,
                startedAt: startedAt,
                errorDescription: errorDescription
            )
        }
    }

    func makeFailureResult(
        feedID: UUID,
        startedAt: Date,
        errorDescription: String
    ) -> FeedRefreshResult {
        FeedRefreshResult.failed(
            feedID: feedID,
            startedAt: startedAt,
            errorDescription: errorDescription
        )
    }

    func makeCancelledResult(feedID: UUID, startedAt: Date) -> FeedRefreshResult {
        FeedRefreshResult.cancelled(
            feedID: feedID,
            startedAt: startedAt,
            errorDescription: "Refresh cancelled"
        )
    }

    func markRefreshAttemptStarted(for feedID: UUID, startedAt: Date) throws {
        var update = FeedMetadataUpdate(updatedAt: startedAt)
        update.lastFetchedAt = startedAt
        _ = try feedRepository.updateMetadata(for: feedID, with: update)
    }

    func markRefreshSucceededWithPayload(
        for feedID: UUID,
        finishedAt: Date,
        saveAfterOperation: Bool = true
    ) throws {
        var update = FeedMetadataUpdate(updatedAt: finishedAt)
        update.lastSuccessfulFetchAt = finishedAt
        update.clearLastSyncError = true
        _ = try feedRepository.updateMetadata(
            for: feedID,
            with: update,
            saveAfterOperation: saveAfterOperation
        )
    }

    func markRefreshFailed(
        feedID: UUID,
        finishedAt: Date,
        errorDescription: String
    ) throws {
        var update = FeedMetadataUpdate(updatedAt: finishedAt)
        update.lastSyncError = errorDescription
        _ = try feedRepository.updateMetadata(for: feedID, with: update)
    }
}
