#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftData

/// Only reached by an explicit Debug Simulator UI-test launch, before any live bootstrap work.
@MainActor
enum UISmokeBootstrap {
    static let feedID = UUID(uuidString: "72000000-0000-0000-0000-000000000001")!
    static let articleID = UUID(uuidString: "72000000-0000-0000-0000-000000000002")!

    static func makeDependencies(environment: [String: String]) throws -> AppDependencies {
        guard let rawURL = environment["RSSREADER_UI_SMOKE_SOURCE_URL"],
              let sourceURL = URL(string: rawURL),
              sourceURL.scheme == "http", sourceURL.host == "127.0.0.1",
              let port = sourceURL.port, (1...65535).contains(port),
              sourceURL.user == nil, sourceURL.password == nil else {
            throw BootstrapError.missingLoopbackSourceURL
        }
        let partition = AppComposition.persistenceModelPartition
        let plan = AppPersistenceConfigurationPlan.make(modelPartition: partition, isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: partition.schema, configurations: plan.modelContainerConfigurations)
        let context = container.mainContext
        let date = Date(timeIntervalSince1970: 1_792_627_200)
        context.insert(Feed(id: feedID, url: "https://ui-smoke.invalid/feed", title: "UI Smoke Feed"))
        context.insert(Article(
            id: articleID, feedID: feedID, feedTitle: "UI Smoke Feed", externalID: "ui-smoke-article",
            url: sourceURL.absoluteString, canonicalURL: sourceURL.absoluteString,
            title: "UI Smoke Article", contentHTML: "<p>Deterministic reader fixture.</p>",
            publishedAt: date, fetchedAt: date, createdAt: date, updatedAt: date
        ))
        if environment["RSSREADER_UI_SMOKE_SEARCH"] == "1" {
            let fixtures: [(String, String?, String?, String?)] = [
                ("Markup Only Article", "<p>Visible reference <a rel=\"noopener nofollow\" href=\"https://invisible.invalid\">link</a></p>", nil, "old noopener"),
                ("Open Reader Article", nil, "<p>Visible Open content.</p>", nil),
                ("Long Reader Article", nil, "<p>" + String(repeating: "Long body ", count: 3_000) + "TailNeedle</p><details><summary>More</summary><p>CollapsedNeedle</p></details>", nil)
            ]
            for (number, fixture) in fixtures.enumerated() {
                context.insert(Article(
                    id: UUID(uuidString: String(format: "85700000-0000-0000-0000-%012d", number + 1))!,
                    feedID: feedID, feedTitle: "UI Smoke Feed", externalID: "search-\(number)",
                    url: sourceURL.absoluteString, title: fixture.0, contentHTML: fixture.2,
                    contentText: fixture.1, searchableText: fixture.3, author: "Search Writer", publishedAt: date
                ))
            }
        }
        context.insert(AppSettings(
            refreshIntervalPreference: .manual, useiCloudSync: false, showUnreadCountBadge: false,
            createdAt: date, updatedAt: date
        ))
        try context.save()
        return AppDependencies(
            logger: ConsoleLogger(), httpClient: OfflineHTTPClient(), feedIconCache: MemoryFeedIconCache(),
            articleImageRuntime: .makeIsolated(),
            sidebarFolderExpansionStore: SidebarFolderExpansionStore(userDefaults: nil),
            modelContainer: container, syncBootstrapPreferenceStore: LocalSyncPreference(),
            backgroundRefreshScheduler: InactiveScheduler(),
            iCloudAccountAvailabilityService: NoAccount(), cloudKitRuntimeEventSource: NoCloudEvents(),
            persistentStoreRemoteChangeSource: NoRemoteChanges()
        )
    }

    enum BootstrapError: Error { case missingLoopbackSourceURL }
}

private nonisolated struct OfflineHTTPClient: HTTPClient {
    func execute(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard request.url.absoluteString == "https://ui-smoke.invalid/added-feed" else {
            throw URLError(.notConnectedToInternet)
        }
        let body = """
        <rss version="2.0"><channel><title>Added Smoke Feed</title>
        <link>https://ui-smoke.invalid/</link><description>Local fixture</description>
        <item><guid>added-smoke-article</guid><title>Added Smoke Article</title>
        <link>https://ui-smoke.invalid/article</link><description>Local article body.</description>
        </item></channel></rss>
        """
        return await MainActor.run {
            HTTPResponse(
                url: request.url, statusCode: 200,
                headers: ["Content-Type": "application/rss+xml"], body: Data(body.utf8)
            )
        }
    }
}

private actor MemoryFeedIconCache: FeedIconCaching {
    private var data: [URL: Data] = [:]
    func cachedImageData(for url: URL) -> Data? { data[url] }
    func storeImageData(_ value: Data, for url: URL) { data[url] = value }
    func hasCachedData() -> Bool { !data.isEmpty }
    func removeAllCachedData() { data.removeAll() }
}

private struct LocalSyncPreference: AppSyncBootstrapPreferenceStoring {
    func currentBootPreference() -> AppSyncBootPreference? { nil }
    func saveBootPreference(_ preference: AppSyncBootPreference) {}
}

private struct NoAccount: ICloudAccountAvailabilityService {
    func currentAvailability() async -> ICloudAccountAvailability { .noAccount }
    func availabilityChanges() -> AsyncStream<ICloudAccountAvailability> { AsyncStream { $0.finish() } }
}

private struct NoCloudEvents: CloudKitRuntimeEventSource {
    func events() -> AsyncStream<CloudKitRuntimeEvent> { AsyncStream { $0.finish() } }
}

private struct NoRemoteChanges: PersistentStoreRemoteChangeSource {
    func events() -> AsyncStream<PersistentStoreRemoteChangeEvent> { AsyncStream { $0.finish() } }
}

@MainActor
private final class InactiveScheduler: BackgroundRefreshScheduling {
    func schedule(using configuration: BackgroundRefreshConfiguration, now: Date) throws -> BackgroundRefreshSchedulePlan? { nil }
    func cancel() {}
    func replace(using configuration: BackgroundRefreshConfiguration, now: Date) throws -> BackgroundRefreshScheduleResult { .cancelled }
}
#endif
