import Foundation
import ImageIO
import UIKit
import UniformTypeIdentifiers

nonisolated enum ArticleImageLoadingError: Error, Equatable, Sendable {
    case unacceptableHTTPStatus(Int)
    case invalidImageData
    case resourceLimitExceeded(AppResourceBudgetViolation)
}

nonisolated struct ArticleImageDisplayTarget: Equatable, Hashable, Sendable {
    let maximumPixelWidth: Int

    init(displayWidth: Double, displayScale: Double) {
        precondition(displayWidth.isFinite && displayWidth > 0)
        precondition(displayScale.isFinite && displayScale > 0)

        let scaledWidth = (displayWidth * displayScale).rounded(.up)
        maximumPixelWidth = max(1, Int(min(scaledWidth, Double(Int.max))))
    }

    init(maximumPixelWidth: Int) {
        precondition(maximumPixelWidth > 0)
        self.maximumPixelWidth = maximumPixelWidth
    }
}

@MainActor
final class ArticleImageLoader {
    static let shared = ArticleImageLoader(
        httpClient: URLSessionHTTPClient(configuration: .articleImageRequestsDefault())
    )

    private let httpClient: any HTTPClient
    private let memoryCache: ArticleImageMemoryCache
    private let diskCache: any ArticleImageDiskCaching
    private let budget: RuntimeImageInputBudget
    private var inFlightLoads: [UUID: InFlightArticleImageLoad] = [:]

    init(
        httpClient: any HTTPClient,
        memoryCache: ArticleImageMemoryCache? = nil,
        diskCache: any ArticleImageDiskCaching = ArticleImageDiskCache.shared,
        budget: RuntimeImageInputBudget = AppComposition.resourceBudgetContract.articleImage
    ) {
        self.httpClient = httpClient
        self.memoryCache = memoryCache ?? .shared
        self.diskCache = diskCache
        self.budget = budget
    }

    func loadImage(from url: URL, displayTarget: ArticleImageDisplayTarget) async throws -> UIImage {
        try Task.checkCancellation()

        if let image = memoryCache.image(
            for: url,
            targetMaximumPixelWidth: displayTarget.maximumPixelWidth
        ) {
            return image
        }

        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                registerWaiter(
                    continuation,
                    id: waiterID,
                    url: url,
                    displayTarget: displayTarget
                )

                if Task.isCancelled {
                    cancelWaiter(id: waiterID)
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                self?.cancelWaiter(id: waiterID)
            }
        }
    }

    func prefetchImage(from url: URL, displayTarget: ArticleImageDisplayTarget) async {
        _ = try? await loadImage(from: url, displayTarget: displayTarget)
    }

    func replacePrefetchReservations(with urls: [URL]) {
        memoryCache.replacePrefetchReservations(with: urls)
    }

    func clearPrefetchReservations() {
        memoryCache.clearPrefetchReservations()
    }

    private func registerWaiter(
        _ continuation: CheckedContinuation<UIImage, Error>,
        id waiterID: UUID,
        url: URL,
        displayTarget: ArticleImageDisplayTarget
    ) {
        if let loadID = reusableInFlightLoadID(for: url, displayTarget: displayTarget) {
            inFlightLoads[loadID]?.waiters[waiterID] = continuation
            return
        }

        let loadID = UUID()
        inFlightLoads[loadID] = InFlightArticleImageLoad(
            url: url,
            displayTarget: displayTarget,
            waiters: [waiterID: continuation],
            task: nil
        )

        let task = Task(priority: Task.currentPriority) { [self] in
            let result: Result<UIImage, Error>
            do {
                result = .success(
                    try await loadImageUncoalesced(from: url, displayTarget: displayTarget)
                )
            } catch {
                result = .failure(error)
            }
            completeInFlightLoad(id: loadID, result: result)
        }

        guard inFlightLoads[loadID] != nil else {
            task.cancel()
            return
        }
        inFlightLoads[loadID]?.task = task
    }

    private func reusableInFlightLoadID(
        for url: URL,
        displayTarget: ArticleImageDisplayTarget
    ) -> UUID? {
        inFlightLoads
            .filter { _, load in
                load.url == url
                    && load.displayTarget.maximumPixelWidth >= displayTarget.maximumPixelWidth
            }
            .min { lhs, rhs in
                lhs.value.displayTarget.maximumPixelWidth
                    < rhs.value.displayTarget.maximumPixelWidth
            }?
            .key
    }

    private func cancelWaiter(id waiterID: UUID) {
        guard let loadID = inFlightLoads.first(where: { _, load in
            load.waiters[waiterID] != nil
        })?.key,
        var load = inFlightLoads[loadID],
        let continuation = load.waiters.removeValue(forKey: waiterID) else {
            return
        }

        continuation.resume(throwing: CancellationError())
        guard load.waiters.isEmpty else {
            inFlightLoads[loadID] = load
            return
        }

        inFlightLoads.removeValue(forKey: loadID)
        load.task?.cancel()
    }

    private func completeInFlightLoad(
        id loadID: UUID,
        result: Result<UIImage, Error>
    ) {
        guard let load = inFlightLoads.removeValue(forKey: loadID) else { return }

        for continuation in load.waiters.values {
            continuation.resume(with: result)
        }
    }

    private func loadImageUncoalesced(
        from url: URL,
        displayTarget: ArticleImageDisplayTarget
    ) async throws -> UIImage {
        try Task.checkCancellation()

        if let image = memoryCache.image(
            for: url,
            targetMaximumPixelWidth: displayTarget.maximumPixelWidth
        ) {
            return image
        }

        let cachedData: Data?
        do {
            cachedData = try await diskCache.data(
                for: url,
                maximumBytes: budget.body.maximumCompressedBodyBytes
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            cachedData = nil
        }

        if let cachedData {
            do {
                let decodedImage = try await decode(
                    cachedData,
                    declaredMIMEType: nil,
                    validatesDetectedMIMEType: true,
                    displayTarget: displayTarget
                )
                try Task.checkCancellation()
                storeInMemory(decodedImage, for: url)
                return decodedImage.image
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                try? await diskCache.removeData(for: url)
            }
        }

        let response: HTTPResponse
        do {
            response = try await httpClient.execute(
                HTTPRequest(
                    url: url,
                    headers: ["Accept": budget.body.allowedMIMETypes.sorted().joined(separator: ", ")],
                    maximumResponseBodyBytes: budget.body.maximumCompressedBodyBytes
                )
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch HTTPClientError.responseBodyTooLarge(let maximumBytes, let actualBytes) {
            throw ArticleImageLoadingError.resourceLimitExceeded(
                .compressedBodySizeExceeded(
                    input: .articleImage,
                    maximumBytes: maximumBytes,
                    actualBytes: actualBytes
                )
            )
        }

        try Task.checkCancellation()

        guard (200...299).contains(response.statusCode) else {
            throw ArticleImageLoadingError.unacceptableHTTPStatus(response.statusCode)
        }

        do {
            try budget.body.validateCompressedBodyByteCount(Int64(response.body.count))
            try budget.body.validateMIMEType(response.contentType)
        } catch let violation as AppResourceBudgetViolation {
            throw ArticleImageLoadingError.resourceLimitExceeded(violation)
        }

        let decodedImage = try await decode(
            response.body,
            declaredMIMEType: response.contentType,
            validatesDetectedMIMEType: false,
            displayTarget: displayTarget
        )
        try Task.checkCancellation()

        storeInMemory(decodedImage, for: url)
        persistInDiskCache(response.body, for: url)
        return decodedImage.image
    }

    private func decode(
        _ data: Data,
        declaredMIMEType: String?,
        validatesDetectedMIMEType: Bool,
        displayTarget: ArticleImageDisplayTarget
    ) async throws -> DecodedArticleImage {
        let budget = budget
        let worker = Task.detached(priority: .userInitiated) {
            try ArticleImageDecoder.decode(
                data,
                declaredMIMEType: declaredMIMEType,
                validatesDetectedMIMEType: validatesDetectedMIMEType,
                displayTarget: displayTarget,
                budget: budget
            )
        }

        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    private func storeInMemory(_ decodedImage: DecodedArticleImage, for url: URL) {
        memoryCache.insert(
            decodedImage.image,
            for: url,
            sourcePixelWidth: decodedImage.sourcePixelWidth,
            sourcePixelHeight: decodedImage.sourcePixelHeight
        )
    }

    private func persistInDiskCache(_ data: Data, for url: URL) {
        let diskCache = diskCache
        Task.detached(priority: .utility) {
            try? await diskCache.insert(data, for: url)
        }
    }
}

@MainActor
private struct InFlightArticleImageLoad {
    let url: URL
    let displayTarget: ArticleImageDisplayTarget
    var waiters: [UUID: CheckedContinuation<UIImage, Error>]
    var task: Task<Void, Never>?
}

extension URLSessionConfiguration {
    nonisolated static func articleImageRequestsDefault() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 60
        configuration.waitsForConnectivity = true
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.urlCache = nil
        return configuration
    }
}

nonisolated enum ArticleImageDownsamplingPolicy {
    static func maximumPixelDimension(
        sourceWidth: Int,
        sourceHeight: Int,
        targetMaximumPixelWidth: Int
    ) -> Int {
        guard sourceWidth > 0, sourceHeight > 0 else { return 1 }

        let scale = min(1, Double(targetMaximumPixelWidth) / Double(sourceWidth))
        let targetWidth = max(1, Int((Double(sourceWidth) * scale).rounded(.up)))
        let targetHeight = max(1, Int((Double(sourceHeight) * scale).rounded(.up)))
        return max(targetWidth, targetHeight)
    }
}

private nonisolated struct DecodedArticleImage: @unchecked Sendable {
    let image: UIImage
    let sourcePixelWidth: Int
    let sourcePixelHeight: Int
}

private nonisolated enum ArticleImageDecoder {
    static func decode(
        _ data: Data,
        declaredMIMEType: String?,
        validatesDetectedMIMEType: Bool,
        displayTarget: ArticleImageDisplayTarget,
        budget: RuntimeImageInputBudget
    ) throws -> DecodedArticleImage {
        try Task.checkCancellation()

        do {
            try budget.body.validateCompressedBodyByteCount(Int64(data.count))
            if let declaredMIMEType {
                try budget.body.validateMIMEType(declaredMIMEType)
            }
        } catch let violation as AppResourceBudgetViolation {
            throw ArticleImageLoadingError.resourceLimitExceeded(violation)
        }

        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let imageSource = CGImageSourceCreateWithData(data as CFData, sourceOptions) else {
            throw ArticleImageLoadingError.invalidImageData
        }

        if validatesDetectedMIMEType {
            guard let typeIdentifier = CGImageSourceGetType(imageSource),
                  let detectedMIMEType = UTType(typeIdentifier as String)?.preferredMIMEType else {
                throw ArticleImageLoadingError.invalidImageData
            }

            do {
                try budget.body.validateMIMEType(detectedMIMEType)
            } catch let violation as AppResourceBudgetViolation {
                throw ArticleImageLoadingError.resourceLimitExceeded(violation)
            }
        }

        guard let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any],
              let sourceWidth = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let sourceHeight = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              sourceWidth > 0,
              sourceHeight > 0 else {
            throw ArticleImageLoadingError.invalidImageData
        }

        do {
            try budget.validatePixelDimensions(width: sourceWidth, height: sourceHeight)
        } catch let violation as AppResourceBudgetViolation {
            throw ArticleImageLoadingError.resourceLimitExceeded(violation)
        }

        try Task.checkCancellation()

        let maximumPixelDimension = ArticleImageDownsamplingPolicy.maximumPixelDimension(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            targetMaximumPixelWidth: displayTarget.maximumPixelWidth
        )
        let thumbnailOptions = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelDimension
        ] as CFDictionary

        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, thumbnailOptions) else {
            throw ArticleImageLoadingError.invalidImageData
        }

        try Task.checkCancellation()

        return DecodedArticleImage(
            image: UIImage(cgImage: cgImage),
            sourcePixelWidth: sourceWidth,
            sourcePixelHeight: sourceHeight
        )
    }
}
