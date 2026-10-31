#if DEBUG && targetEnvironment(simulator)
import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Infrastructure / UI Smoke Bootstrap")
@MainActor
struct UISmokeBootstrapTests {
    @Test(arguments: ["", "https://example.com/article", "http://localhost:8000/article", "http://127.0.0.1/article"])
    func refusesMissingOrNonLoopbackFixtureURL(_ rawURL: String) {
        #expect(throws: UISmokeBootstrap.BootstrapError.self) {
            _ = try UISmokeBootstrap.makeDependencies(environment: ["RSSREADER_UI_SMOKE_SOURCE_URL": rawURL])
        }
    }

    @Test
    func localAddFeedFixturePreviewsSavesAndRefreshesWithoutNetwork() async throws {
        let dependencies = try UISmokeBootstrap.makeDependencies(environment: [
            "RSSREADER_UI_SMOKE_SOURCE_URL": "http://127.0.0.1:8000/article"
        ])
        let appState = AppState()
        let controller = FeedManagementScreenController()
        controller.handleScenarioSelection(.addFeed, dependencies: dependencies)
        controller.handleAddFeedURLChange("https://ui-smoke.invalid/added-feed")
        await controller.handleAddFeedPrimaryAction(dependencies: dependencies, appState: appState)
        await controller.handleAddFeedPrimaryAction(dependencies: dependencies, appState: appState)
        await dependencies.appActions.waitForScheduledFeedSaveRefreshes()

        let feed = try #require(try dependencies.feedRepository?.fetchFeed(url: "https://ui-smoke.invalid/added-feed"))
        #expect(feed.lastSuccessfulFetchAt != nil)
        #expect(try dependencies.articleRepository?.fetchArticles(feedID: feed.id).map(\.title) == ["Added Smoke Article"])
    }

    @Test
    func launchesHaveIndependentStoresSettingsAndCaches() async throws {
        let environment = ["RSSREADER_UI_SMOKE_SOURCE_URL": "http://127.0.0.1:8000/article"]
        let first = try UISmokeBootstrap.makeDependencies(environment: environment)
        let firstContainer = try #require(first.modelContainer)
        #expect(firstContainer.configurations.allSatisfy { $0.isStoredInMemoryOnly })
        #expect(first.syncCoordinator == nil)
        #expect(await first.iCloudAccountAvailabilityService.currentAvailability() == .noAccount)
        let firstArticle = try #require(firstContainer.mainContext.fetch(FetchDescriptor<Article>()).first)
        firstArticle.title = "Changed in previous launch"
        try firstContainer.mainContext.save()
        _ = try first.appSettingsService?.updateSettings(AppSettingsPatch(articleOpeningMode: .safariView))
        let iconURL = URL(string: "https://ui-smoke.invalid/icon.png")!
        try await first.feedIconCache.storeImageData(Data([1, 2, 3]), for: iconURL)
        first.sidebarFolderExpansionStore.toggleExpansion(folderID: UISmokeBootstrap.feedID)
        await #expect(throws: URLError.self) {
            _ = try await first.httpClient.execute(HTTPRequest(url: iconURL, maximumResponseBodyBytes: 1024))
        }

        let second = try UISmokeBootstrap.makeDependencies(environment: environment)
        let secondContainer = try #require(second.modelContainer)
        let articles = try secondContainer.mainContext.fetch(FetchDescriptor<Article>())
        #expect(articles.count == 1)
        #expect(articles.first?.id == UISmokeBootstrap.articleID)
        #expect(articles.first?.title == "UI Smoke Article")
        let settings = try secondContainer.mainContext.fetch(FetchDescriptor<AppSettings>())
        #expect(settings.first?.articleOpeningMode == .feedReader)
        #expect(settings.first?.useiCloudSync == false)
        #expect(try await second.feedIconCache.hasCachedData() == false)
        #expect(try await second.articleImageCache.hasCachedImages() == false)
        #expect(second.sidebarFolderExpansionStore.collapsedFolderIDs.isEmpty)
    }
}
#endif
