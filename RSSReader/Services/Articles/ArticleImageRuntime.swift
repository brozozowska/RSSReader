import Foundation
import UIKit

@MainActor
protocol ArticleImageLoading: AnyObject {
    func cachedImage(for url: URL, targetMaximumPixelWidth: Int?) -> UIImage?
    func loadImage(from url: URL, displayTarget: ArticleImageDisplayTarget) async throws -> UIImage
}

@MainActor
protocol ArticleImageCacheManaging: AnyObject {
    var hasMemoryImages: Bool { get }
    func hasCachedImages() async throws -> Bool
    func clearCachedImages() async throws
}

/// One cache pair and one coalescing loader for visible images and route-owned prefetch.
@MainActor
final class ArticleImageRuntime: ArticleImageCacheManaging {
    let imageLoading: any ArticleImageLoading
    let prefetchCoordinator: ReaderAdjacentArticleImagePrefetchCoordinator
    private let memoryCache: ArticleImageMemoryCache
    private let diskCache: ArticleImageDiskCache

    convenience init(httpClient: any HTTPClient, directoryURL: URL) {
        self.init(httpClient: httpClient, diskCache: ArticleImageDiskCache(directoryURL: directoryURL))
    }

    init(
        httpClient: any HTTPClient,
        memoryCache: ArticleImageMemoryCache? = nil,
        diskCache: ArticleImageDiskCache
    ) {
        let memoryCache = memoryCache ?? ArticleImageMemoryCache()
        let loader = ArticleImageLoader(
            httpClient: httpClient,
            memoryCache: memoryCache,
            diskCache: diskCache
        )
        self.memoryCache = memoryCache
        self.diskCache = diskCache
        self.imageLoading = loader
        self.prefetchCoordinator = ReaderAdjacentArticleImagePrefetchCoordinator(imagePrefetcher: loader)
    }

    static func makeLive() -> ArticleImageRuntime {
        ArticleImageRuntime(
            httpClient: URLSessionHTTPClient(configuration: .articleImageRequestsDefault()),
            diskCache: ArticleImageDiskCache()
        )
    }

    /// Safe fallback for previews and dependency fixtures: no live HTTP or default cache directory.
    static func makeIsolated(memoryCache: ArticleImageMemoryCache? = nil) -> ArticleImageRuntime {
        ArticleImageRuntime(
            httpClient: UnavailableArticleImageHTTPClient(),
            memoryCache: memoryCache,
            diskCache: ArticleImageDiskCache(
                directoryURL: FileManager.default.temporaryDirectory
                    .appendingPathComponent("RSSReaderArticleImages-" + UUID().uuidString, isDirectory: true)
            )
        )
    }

    var hasMemoryImages: Bool { memoryCache.hasImages }

    func hasCachedImages() async throws -> Bool {
        let hasDiskImages = try await diskCache.isEmpty() == false
        return hasMemoryImages || hasDiskImages
    }

    /// Clears the current contents. Active loads and best-effort disk writes may populate them again.
    func clearCachedImages() async throws {
        memoryCache.removeAllImages()
        try await diskCache.removeAll()
    }
}

private nonisolated struct UnavailableArticleImageHTTPClient: HTTPClient {
    func execute(_ request: HTTPRequest) async throws -> HTTPResponse {
        throw URLError(.notConnectedToInternet)
    }
}
