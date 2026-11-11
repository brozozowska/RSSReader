import Foundation

extension AppActionRouter {
    @MainActor
    func refreshFeed(id feedID: UUID, initialFetchSnapshot: FeedInitialFetchSnapshot? = nil) async -> FeedRefreshResult? {
        let target = FeedIssue.Target.operation(.selection(.feed(feedID)))
        let token = dependencies.feedIssues.begin(target)
        let startedAt = Date()
        guard let feedRefreshService else {
            logger.error("Feed refresh service is unavailable")
            dependencies.feedIssues.finish(
                target, token: token, attemptedAt: startedAt, reason: .infrastructure,
                cancelled: Task.isCancelled, retryAvailable: false
            )
            return nil
        }

        let result = await feedRefreshService.refresh(feedID: feedID, initialFetchSnapshot: initialFetchSnapshot)
        dependencies.feedIssues.finish(
            target, token: token, attemptedAt: startedAt, reason: nil, cancelled: result.status == .cancelled
        )
        let cleanupResult = cleanupArticlesUsingCurrentSettings(scope: .feedIDs([result.feedID]))
        recordRefreshLifecycleDiagnostics(refreshResult: result, cleanupResult: cleanupResult)
        await refreshUnreadAppIconBadgeCount()
        return result
    }

    @MainActor
    func refreshAllFeeds() async -> FeedRefreshBatchResult? {
        await refreshAllFeeds(operation: .selection(.allFeeds))
    }

    @MainActor
    private func refreshAllFeeds(operation: FeedRefreshOperation) async -> FeedRefreshBatchResult {
        let result = await runRefreshOperation(operation, retryAvailable: feedRefreshService != nil) {
            guard let feedRefreshService else {
                logger.error("Feed refresh service is unavailable")
                return batchInfrastructureFailure()
            }
            return await feedRefreshService.refreshAllActiveFeeds()
        }
        recordManualRefreshBatchDiagnostics(
            result,
            phase: "initial",
            requestedTargetFeedIDs: result.targetFeedIDs
        )
        recordFeedsRefreshIfNeeded(from: result)
        if feedRefreshService != nil {
            cleanupArticlesUsingCurrentSettings(scope: .allFeeds)
            await refreshUnreadAppIconBadgeCount()
        }
        return result
    }

    @MainActor
    func retryFeeds(
        _ feedIDs: [UUID],
        context: ManualFeedRefreshContext,
        using appState: AppState,
        requestsArticleListReload: Bool = true
    ) async -> FeedRefreshBatchResult? {
        let requestedFeedIDs = uniquePreservingOrder(feedIDs)
        let result = await runRefreshOperation(
            .failedFeeds(context.scope),
            retryAvailable: feedRefreshService != nil && feedRepository != nil,
            retryFeedIDs: requestedFeedIDs
        ) {
            guard let feedRefreshService, let feedRepository else {
                logger.error("Refresh dependencies are unavailable for failed-feed retry")
                return batchInfrastructureFailure(targetFeedIDs: requestedFeedIDs)
            }
            do {
                let activeFeedIDs = Set(try feedRepository.fetchActiveFeeds().map(\.id))
                let retryFeedIDs = requestedFeedIDs.filter(activeFeedIDs.contains)
                if !Task.isCancelled {
                    for feedID in requestedFeedIDs where !activeFeedIDs.contains(feedID) {
                        dependencies.feedIssues.removeFeed(feedID)
                    }
                }
                return await feedRefreshService.refreshFeeds(retryFeedIDs)
            } catch {
                logger.error("Failed to resolve active feeds for failed-feed retry: \(error)")
                return batchInfrastructureFailure(targetFeedIDs: requestedFeedIDs)
            }
        }
        recordManualRefreshBatchDiagnostics(
            result,
            phase: "retry",
            requestedTargetFeedIDs: requestedFeedIDs
        )
        guard result.batchFailureReason == nil else { return result }
        if context.scope == .allFeeds {
            recordFeedsRefreshIfNeeded(from: result)
        }
        cleanupArticlesUsingCurrentSettings(scope: .feedIDs(result.targetFeedIDs))
        await refreshUnreadAppIconBadgeCount()
        appState.requestSidebarReload()
        if requestsArticleListReload {
            appState.requestArticleListReload()
        }
        return result
    }

    @MainActor
    func refreshSelection(
        _ context: ManualFeedRefreshContext,
        using appState: AppState,
        requestsArticleListReload: Bool = true
    ) async -> FeedRefreshBatchResult? {
        let result: FeedRefreshBatchResult
        switch context.scope {
        case .feed(let feedID):
            if let refreshResult = await refreshFeed(id: feedID) {
                result = FeedRefreshBatchResult(
                    startedAt: refreshResult.startedAt,
                    finishedAt: refreshResult.finishedAt,
                    results: [refreshResult]
                )
            } else {
                result = batchInfrastructureFailure()
            }
        case .folder(let folderName):
            result = await refreshFeeds(in: folderName)
        case .allFeeds:
            result = await refreshAllFeeds(operation: .selection(.allFeeds))
        }

        appState.requestSidebarReload()
        if requestsArticleListReload {
            appState.requestArticleListReload()
        }

        return result
    }

    @MainActor
    func refreshFeedsForBackground() async -> BackgroundRefreshServiceExecutionResult {
        let target = FeedIssue.Target.operation(.background)
        let token = dependencies.feedIssues.begin(target)
        let startedAt = Date()
        guard let backgroundRefreshService else {
            dependencies.feedIssues.finish(
                target, token: token, attemptedAt: startedAt, reason: .infrastructure,
                cancelled: Task.isCancelled, retryAvailable: feedRefreshService != nil
            )
            logger.debug(
                "Background refresh dependencies trace outcome=serviceUnavailable operation=executeBackgroundAppRefresh"
            )
            return .failedToStart(.feedRefreshServiceUnavailable)
        }

        let result = await backgroundRefreshService.performScheduledRefresh()
        switch result {
        case .executed(let refreshResult):
            dependencies.feedIssues.finish(
                target, token: token, attemptedAt: startedAt,
                reason: refreshResult.batchResult.batchFailureReason, cancelled: Task.isCancelled
            )
            recordFeedsRefreshIfNeeded(from: refreshResult.batchResult)
            cleanupFeedFetchLogs()
            await refreshUnreadAppIconBadgeCount()
        case .failedToStart:
            dependencies.feedIssues.finish(
                target, token: token, attemptedAt: startedAt, reason: .infrastructure,
                cancelled: Task.isCancelled, retryAvailable: feedRefreshService != nil
            )
        case .skippedManual:
            dependencies.feedIssues.finish(target, token: token, attemptedAt: startedAt, reason: nil, cancelled: true)
        }
        return result
    }

    @MainActor
    private func recordFeedsRefreshIfNeeded(from result: FeedRefreshBatchResult) {
        guard result.isCompleteSuccess,
              result.summary.fetchedCount + result.summary.notModifiedCount > 0 else {
            return
        }

        do {
            _ = try appSettingsService?.updateSettings(
                AppSettingsPatch(
                    lastFeedsRefreshAt: result.finishedAt,
                    updatedAt: result.finishedAt
                )
            )
        } catch {
            logger.error("Failed to persist feeds refresh timestamp: \(error)")
        }
    }

    @MainActor
    private func refreshFeeds(in folderName: String) async -> FeedRefreshBatchResult {
        let result = await runRefreshOperation(
            .selection(.folder(folderName)),
            retryAvailable: feedRefreshService != nil && feedRepository != nil
        ) {
            guard let feedRefreshService, let feedRepository else {
                logger.error("Refresh dependencies are unavailable for folder refresh")
                return batchInfrastructureFailure()
            }

            do {
                let folderFeedIDs = try feedRepository.fetchActiveFeeds()
                    .filter { $0.folder?.name == folderName }
                    .map(\.id)
                return await feedRefreshService.refreshFeeds(folderFeedIDs)
            } catch {
                logger.error("Failed to load folder feeds for refresh: \(error)")
                return batchInfrastructureFailure()
            }
        }
        if result.batchFailureReason == nil {
            cleanupArticlesUsingCurrentSettings(scope: .feedIDs(result.results.map(\.feedID)))
            await refreshUnreadAppIconBadgeCount()
        }
        return result
    }

    @MainActor
    func retryFeedIssue(_ target: FeedIssue.Target, using appState: AppState) async -> FeedRefreshBatchResult? {
        guard dependencies.feedIssues.issues[target]?.canRetry == true else { return nil }

        switch target {
        case .feed(let feedID):
            return await retryFeeds(
                [feedID],
                context: refreshContext(for: .feed(feedID)),
                using: appState
            )
        case .operation(.selection(let scope)):
            return await refreshSelection(refreshContext(for: scope), using: appState)
        case .operation(.failedFeeds(let scope)):
            guard let feedIDs = dependencies.feedIssues.retryFeedIDs(for: .failedFeeds(scope)) else { return nil }
            return await retryFeeds(feedIDs, context: refreshContext(for: scope), using: appState)
        case .operation(.background):
            let result = await refreshAllFeeds(operation: .background)
            appState.requestSidebarReload()
            appState.requestArticleListReload()
            return result
        }
    }

    private func refreshContext(for scope: ManualFeedRefreshScope) -> ManualFeedRefreshContext {
        let selection: SidebarSelection
        switch scope {
        case .allFeeds: selection = .inbox
        case .folder(let name): selection = .folder(name)
        case .feed(let id): selection = .feed(id)
        }
        return ManualFeedRefreshContext(selection: selection, sidebarArticleFilter: .allItems)
    }

    @MainActor
    private func runRefreshOperation(
        _ operation: FeedRefreshOperation,
        retryAvailable: Bool,
        retryFeedIDs: [UUID] = [],
        execute: () async -> FeedRefreshBatchResult
    ) async -> FeedRefreshBatchResult {
        let target = FeedIssue.Target.operation(operation)
        let token = dependencies.feedIssues.begin(target)
        let startedAt = Date()
        let result = await execute()
        dependencies.feedIssues.finish(
            target,
            token: token,
            attemptedAt: startedAt,
            reason: result.batchFailureReason,
            cancelled: Task.isCancelled,
            retryAvailable: retryAvailable,
            retryFeedIDs: retryFeedIDs
        )
        return result
    }

    private func batchInfrastructureFailure(targetFeedIDs: [UUID] = []) -> FeedRefreshBatchResult {
        let now = Date()
        return FeedRefreshBatchResult(
            startedAt: now,
            finishedAt: now,
            results: [],
            targetFeedIDs: targetFeedIDs,
            batchFailureReason: .infrastructure,
            batchErrorDescription: "Unable to prepare feed refresh"
        )
    }

    @MainActor
    private func recordRefreshLifecycleDiagnostics(
        refreshResult: FeedRefreshResult,
        cleanupResult: ArticleRetentionCleanupResult?
    ) {
        let fetchedEntryCount = refreshResult.status == .fetched
            ? max(0, refreshResult.processedEntryCount - refreshResult.rejectedEntryCount)
            : 0
        logger.info(
            "Feed refresh lifecycle completed feed=\(refreshResult.feedID.uuidString) "
                + "status=\(refreshResult.status.rawValue) "
                + "fetchedEntries=\(fetchedEntryCount) "
                + "upsertedEntries=\(refreshResult.upsertedEntryCount) "
                + "reconciledEntries=\(refreshResult.reconciledEntryCount) "
                + "deletedByRetention=\(cleanupResult?.deletedCount ?? 0) "
                + "retentionCleanupCompleted=\(cleanupResult != nil)"
        )
    }

    @MainActor
    private func recordManualRefreshBatchDiagnostics(
        _ result: FeedRefreshBatchResult,
        phase: String,
        requestedTargetFeedIDs: [UUID]
    ) {
        let requestedTargets = requestedTargetFeedIDs.map(\.uuidString).joined(separator: ",")
        let targets = result.targetFeedIDs.map(\.uuidString).joined(separator: ",")
        let outcomes = result.results.map {
            "\($0.feedID.uuidString):\($0.status.rawValue)"
        }.joined(separator: ",")
        let retryTargets = result.retryFeedIDs.map(\.uuidString).joined(separator: ",")
        logger.info(
            "Manual feed refresh batch phase=\(phase) "
                + "requestedTargets=[\(requestedTargets)] "
                + "targets=[\(targets)] outcomes=[\(outcomes)] "
                + "retryTargets=[\(retryTargets)] "
                + "batchError=\(result.batchErrorDescription ?? "none")"
        )
    }

    private func uniquePreservingOrder(_ feedIDs: [UUID]) -> [UUID] {
        var seen = Set<UUID>()
        return feedIDs.filter { seen.insert($0).inserted }
    }
}
