import Foundation

extension AppComposition {
    static func configureSharedURLCache(
        configuration: AppURLCacheConfiguration = .articleImageLoading
    ) {
        configuration.applyAsSharedURLCache()
    }
}

struct AppURLCacheConfiguration: Equatable {
    let memoryCapacity: Int
    let diskCapacity: Int
    let diskPath: String

    static let articleImageLoading = AppURLCacheConfiguration(
        memoryCapacity: 50 * 1024 * 1024,
        diskCapacity: 200 * 1024 * 1024,
        diskPath: "RSSReaderArticleImageURLCache"
    )

    func makeURLCache() -> URLCache {
        URLCache(
            memoryCapacity: memoryCapacity,
            diskCapacity: diskCapacity,
            diskPath: diskPath
        )
    }

    func applyAsSharedURLCache() {
        URLCache.shared = makeURLCache()
    }
}
