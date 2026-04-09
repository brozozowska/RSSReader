import Foundation

public protocol SourceIconCaching: Sendable {
    func imageData(for url: URL) async throws -> Data
}

public enum SourceIconCacheError: Error {
    case invalidResponseStatusCode(Int)
    case emptyImageData
}

public actor SourceIconCacheService: SourceIconCaching {
    private let httpClient: any HTTPClient
    private let cache: SourceIconMemoryCache
    private var inFlightTasks: [URL: Task<Data, Error>] = [:]

    public init(
        httpClient: any HTTPClient,
        cache: SourceIconMemoryCache? = nil
    ) {
        self.httpClient = httpClient
        self.cache = cache ?? SourceIconMemoryCache()
    }

    public func imageData(for url: URL) async throws -> Data {
        if let cachedData = await cache.data(for: url) {
            return cachedData
        }

        if let task = inFlightTasks[url] {
            return try await task.value
        }

        let task = Task<Data, Error> {
            let response = try await httpClient.execute(HTTPRequest(url: url))

            guard (200...299).contains(response.statusCode) else {
                throw SourceIconCacheError.invalidResponseStatusCode(response.statusCode)
            }

            guard response.body.isEmpty == false else {
                throw SourceIconCacheError.emptyImageData
            }

            await cache.insert(response.body, for: url)
            return response.body
        }

        inFlightTasks[url] = task
        defer { inFlightTasks[url] = nil }

        return try await task.value
    }
}

public actor SourceIconMemoryCache {
    private let storage = NSCache<NSURL, NSData>()

    public init(countLimit: Int = 256) {
        storage.countLimit = countLimit
    }

    func data(for url: URL) -> Data? {
        storage.object(forKey: url as NSURL) as Data?
    }

    func insert(_ data: Data, for url: URL) {
        storage.setObject(data as NSData, forKey: url as NSURL)
    }
}
