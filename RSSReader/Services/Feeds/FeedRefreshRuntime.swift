import Foundation

extension FeedRefreshService {
    func refresh(feedID: UUID) async -> FeedRefreshResult {
        switch inFlightPolicy {
        case .shareExistingTaskResult:
            return await awaitSharedInFlightRefresh(feedID: feedID)
        }
    }

    private func awaitSharedInFlightRefresh(
        feedID: UUID
    ) async -> FeedRefreshResult {
        let waiterID = UUID()
        let waiterStartedAt = Date()

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                registerInFlightWaiter(
                    id: waiterID,
                    startedAt: waiterStartedAt,
                    continuation: continuation,
                    feedID: feedID
                )

                if Task.isCancelled {
                    cancelInFlightWaiter(id: waiterID, feedID: feedID)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelInFlightWaiter(id: waiterID, feedID: feedID)
            }
        }
    }

    private func registerInFlightWaiter(
        id waiterID: UUID,
        startedAt: Date,
        continuation: CheckedContinuation<FeedRefreshResult, Never>,
        feedID: UUID
    ) {
        let waiter = FeedRefreshInFlightWaiter(
            startedAt: startedAt,
            continuation: continuation
        )

        if var inFlightTask = inFlightRefreshTasks[feedID] {
            logger.info("Joining in-flight refresh for feed \(feedID.uuidString)")
            inFlightTask.waiters[waiterID] = waiter
            inFlightRefreshTasks[feedID] = inFlightTask
            return
        }

        let inFlightTaskID = UUID()
        let task = Task<FeedRefreshResult, Never> { @MainActor [self, feedID] in
            let result = await performRefresh(feedID: feedID)
            completeInFlightRefresh(
                id: inFlightTaskID,
                feedID: feedID,
                result: result
            )
            return result
        }

        inFlightRefreshTasks[feedID] = FeedRefreshInFlightTask(
            id: inFlightTaskID,
            task: task,
            waiters: [waiterID: waiter]
        )
    }

    private func cancelInFlightWaiter(id waiterID: UUID, feedID: UUID) {
        guard var inFlightTask = inFlightRefreshTasks[feedID],
              let waiter = inFlightTask.waiters.removeValue(forKey: waiterID) else {
            return
        }

        switch inFlightCallerCancellationPolicy {
        case .cancelSharedTaskWhenLastWaiterCancels:
            if inFlightTask.waiters.isEmpty {
                inFlightTask.task.cancel()
            }
        }

        inFlightRefreshTasks[feedID] = inFlightTask
        waiter.continuation.resume(
            returning: makeCancelledResult(
                feedID: feedID,
                startedAt: waiter.startedAt
            )
        )
    }

    private func completeInFlightRefresh(
        id inFlightTaskID: UUID,
        feedID: UUID,
        result: FeedRefreshResult
    ) {
        guard let inFlightTask = inFlightRefreshTasks[feedID],
              inFlightTask.id == inFlightTaskID else {
            return
        }

        inFlightRefreshTasks.removeValue(forKey: feedID)
        for waiter in inFlightTask.waiters.values {
            waiter.continuation.resume(returning: result)
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
            persistRefreshFailureStateBestEffort(
                feedID: feedID,
                finishedAt: finishedAt,
                errorDescription: errorDescription
            )
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

    func persistRefreshFailureStateBestEffort(
        feedID: UUID,
        finishedAt: Date,
        errorDescription: String
    ) {
        do {
            try markRefreshFailed(
                feedID: feedID,
                finishedAt: finishedAt,
                errorDescription: errorDescription
            )
        } catch {
            feedRepository.rollback()
            logger.error(
                "refresh_failure_state_persistence_failed feedID=\(feedID.uuidString) "
                    + "error=\(String(describing: error)); failed refresh result preserved"
            )
        }
    }
}
