import Foundation

// MARK: - Factory
extension AppDependencies {
    static func makeDefaultLogger(category: String = "app") -> Logging {
#if DEBUG
        let baseLogger = OSLogger(category: category)
        return FilteredLogger(minLevel: .debug, base: baseLogger)
#else
        let baseLogger = OSLogger(category: category)
        return FilteredLogger(minLevel: .info, base: baseLogger)
#endif
    }

    static func makeDefault() -> AppDependencies {
        let logger = makeDefaultLogger()
        return AppDependencies(logger: logger)
    }

}

extension AppDependencies {
    static func makeFeedFetcher(
        httpClient: any HTTPClient
    ) -> any FeedFetching {
        FeedFetcher(httpClient: httpClient)
    }
}
