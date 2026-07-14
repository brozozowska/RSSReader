import Foundation

nonisolated enum OPMLImportFileError: Error, Equatable, Sendable {
    case notRegularFile
}

nonisolated protocol OPMLImportFileLoading: Sendable {
    func loadPreview(
        fileURL: URL,
        existingFeeds: [FeedManagementFeedSummary],
        existingFolders: [FeedManagementFolderSummary]
    ) async throws -> OPMLImportPreviewPlan
}

nonisolated struct BoundedOPMLImportFileLoader: OPMLImportFileLoading, Sendable {
    private let budget: RuntimeXMLInputBudget
    private let readChunkSize: Int

    init(
        budget: RuntimeXMLInputBudget = AppComposition.resourceBudgetContract.opml,
        readChunkSize: Int = 64 * 1024
    ) {
        precondition(readChunkSize > 0)
        self.budget = budget
        self.readChunkSize = readChunkSize
    }

    func loadPreview(
        fileURL: URL,
        existingFeeds: [FeedManagementFeedSummary],
        existingFolders: [FeedManagementFolderSummary]
    ) async throws -> OPMLImportPreviewPlan {
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()

            let didStartAccessing = fileURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }

            let data = try readBoundedData(from: fileURL)
            try Task.checkCancellation()
            let document = try OPMLParserService.parse(data)
            try Task.checkCancellation()
            return try OPMLImportPreviewPlanner.makePlanCheckingCancellation(
                document: document,
                existingFeeds: existingFeeds,
                existingFolders: existingFolders
            )
        }

        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private func readBoundedData(from fileURL: URL) throws -> Data {
        let resourceValues = try fileURL.resourceValues(
            forKeys: [.fileSizeKey, .isRegularFileKey]
        )
        if resourceValues.isRegularFile == false {
            throw OPMLImportFileError.notRegularFile
        }

        if let declaredFileSize = resourceValues.fileSize {
            try budget.body.validateCompressedBodyByteCount(Int64(declaredFileSize))
        }

        let fileHandle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? fileHandle.close()
        }

        let maximumBytes = budget.body.maximumCompressedBodyBytes
        var data = Data()
        if let declaredFileSize = resourceValues.fileSize {
            data.reserveCapacity(Int(min(Int64(declaredFileSize), maximumBytes)))
        }

        while true {
            try Task.checkCancellation()

            let remainingBytesIncludingOverflowSentinel = maximumBytes + 1 - Int64(data.count)
            let nextReadCount = Int(
                min(Int64(readChunkSize), remainingBytesIncludingOverflowSentinel)
            )
            let chunk = try fileHandle.read(upToCount: nextReadCount) ?? Data()
            guard chunk.isEmpty == false else { break }

            data.append(chunk)
            try budget.body.validateCompressedBodyByteCount(Int64(data.count))
        }

        try Task.checkCancellation()
        return data
    }
}
