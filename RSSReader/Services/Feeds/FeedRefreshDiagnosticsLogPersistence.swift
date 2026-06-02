import Foundation

extension FeedRefreshService {
    func persistRefreshLog(
        feedID: UUID,
        status: FeedRefreshStatus,
        httpCode: Int?,
        diagnosticsSummary: FeedRefreshDiagnosticsSummary,
        errorDescription: String?,
        finishedAt: Date,
        baseMessage: String? = nil
    ) throws {
        guard let feedFetchLogRepository else { return }

        let logEntry = FeedFetchLogEntry(
            feedID: feedID,
            status: normalizedLogStatus(for: status),
            httpCode: httpCode,
            message: logMessage(
                baseMessage: baseMessage,
                diagnosticsSummary: diagnosticsSummary,
                errorDescription: errorDescription
            ),
            createdAt: finishedAt
        )

        try feedFetchLogRepository.insert(logEntry)
    }

    func normalizedLogStatus(for status: FeedRefreshStatus) -> String {
        switch status {
        case .fetched:
            "fetched"
        case .notModified:
            "not_modified"
        case .failed:
            "failed"
        case .cancelled:
            "cancelled"
        }
    }

    func logMessage(
        baseMessage: String?,
        diagnosticsSummary: FeedRefreshDiagnosticsSummary,
        errorDescription: String?
    ) -> String? {
        var parts: [String] = []

        if let baseMessage, baseMessage.isEmpty == false {
            parts.append(baseMessage)
        }

        parts.append(
            "diagnostics(parser_anomalies=\(diagnosticsSummary.parserAnomalyCount), rejected_entries=\(diagnosticsSummary.rejectedEntryCount))"
        )

        if let errorDescription, errorDescription.isEmpty == false {
            parts.append("error=\(errorDescription)")
        }

        return parts.isEmpty ? nil : parts.joined(separator: "; ")
    }

    func httpCode(from error: Error) -> Int? {
        guard case .invalidStatusCode(let statusCode) = error as? FeedFetchError else {
            return nil
        }
        return statusCode
    }

    func diagnosticsSummary(for diagnostics: FeedParsePipelineDiagnostics) -> FeedRefreshDiagnosticsSummary {
        diagnosticsPolicy.makeSummary(from: diagnostics)
    }

    func diagnosticsAreSoftFailure(_ diagnostics: FeedParsePipelineDiagnostics) -> Bool {
        diagnosticsPolicy.treatsDiagnosticsAsSoftFailure(diagnostics)
    }

    func logDiagnosticsIfNeeded(
        _ diagnostics: FeedParsePipelineDiagnostics,
        feedID: UUID
    ) {
        guard diagnostics.hasIssues else { return }

        if diagnosticsPolicy.logsParserAnomalies, diagnostics.parserAnomalies.isEmpty == false {
            let summary = "Feed \(feedID.uuidString) parser anomalies: \(diagnostics.parserAnomalies.count)"
            logger.info(summary)
            for anomaly in diagnostics.parserAnomalies {
                logger.info("Feed \(feedID.uuidString) anomaly [\(String(describing: anomaly.kind))]: \(anomaly.message)")
            }
        }

        if diagnosticsPolicy.logsRejectedEntries, diagnostics.rejectedEntries.isEmpty == false {
            logger.info("Feed \(feedID.uuidString) rejected entries: \(diagnostics.rejectedEntries.count)")
            for rejectedEntry in diagnostics.rejectedEntries {
                let reasons = rejectedEntry.reasons.map(\.rawValue).joined(separator: ", ")
                logger.info("Feed \(feedID.uuidString) rejected entry reasons: \(reasons)")
            }
        }

        if diagnosticsAreSoftFailure(diagnostics) {
            logger.info("Feed \(feedID.uuidString) refresh diagnostics treated as soft failure")
        }
    }
}
