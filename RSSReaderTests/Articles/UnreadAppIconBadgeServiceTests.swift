import Foundation
import Testing
@testable import RSSReader

@Suite("Articles / Unread App Icon Badge Service")
@MainActor
struct UnreadAppIconBadgeServiceTests {
    @Test
    func refreshBadgeCountAppliesTotalUnreadCountAcrossActiveFeeds() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appSettingsService = try #require(harness.dependencies.appSettingsService)
        try appSettingsService.updateSettings(AppSettingsPatch(showUnreadCountBadge: true))
        let firstFeed = try #require(try harness.insertFeeds(urls: ["https://example.com/first.xml"]).first)
        let secondFeed = try #require(try harness.insertFeeds(urls: ["https://example.com/second.xml"]).last)
        _ = try harness.insertArticle(
            feed: firstFeed,
            externalID: "first-unread",
            url: "https://example.com/articles/first-unread",
            title: "First Unread"
        )
        let readArticle = try harness.insertArticle(
            feed: firstFeed,
            externalID: "first-read",
            url: "https://example.com/articles/first-read",
            title: "First Read"
        )
        let hiddenArticle = try harness.insertArticle(
            feed: secondFeed,
            externalID: "second-hidden",
            url: "https://example.com/articles/second-hidden",
            title: "Second Hidden"
        )
        _ = try harness.insertArticle(
            feed: secondFeed,
            externalID: "second-unread",
            url: "https://example.com/articles/second-unread",
            title: "Second Unread"
        )
        _ = try harness.articleStateRepository.upsert(
            feedID: readArticle.feedID,
            articleExternalID: readArticle.externalID,
            update: ArticleStateUpsert(isRead: true, updatedAt: .now)
        )
        _ = try harness.articleStateRepository.upsert(
            feedID: hiddenArticle.feedID,
            articleExternalID: hiddenArticle.externalID,
            update: ArticleStateUpsert(isHidden: true, updatedAt: .now)
        )
        let badgeApplier = RecordingAppIconBadgeApplier()
        let service = UnreadAppIconBadgeService(
            logger: TestLogger(),
            feedRepository: harness.feedRepository,
            articleStateRepository: harness.articleStateRepository,
            appSettingsService: appSettingsService,
            badgeApplier: badgeApplier
        )

        await service.refreshBadgeCount()

        #expect(badgeApplier.appliedCounts == [2])
    }

    @Test
    func refreshBadgeCountClearsBadgeWhenThereAreNoActiveFeeds() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appSettingsService = try #require(harness.dependencies.appSettingsService)
        try appSettingsService.updateSettings(AppSettingsPatch(showUnreadCountBadge: true))
        let badgeApplier = RecordingAppIconBadgeApplier()
        let service = UnreadAppIconBadgeService(
            logger: TestLogger(),
            feedRepository: harness.feedRepository,
            articleStateRepository: harness.articleStateRepository,
            appSettingsService: appSettingsService,
            badgeApplier: badgeApplier
        )

        await service.refreshBadgeCount()

        #expect(badgeApplier.appliedCounts == [0])
    }

    @Test
    func refreshBadgeCountSkipsApplyingBadgeWhenAuthorizationIsUnavailable() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appSettingsService = try #require(harness.dependencies.appSettingsService)
        try appSettingsService.updateSettings(AppSettingsPatch(showUnreadCountBadge: true))
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/feed.xml"]).first)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "unread",
            url: "https://example.com/articles/unread",
            title: "Unread"
        )
        let badgeApplier = RecordingAppIconBadgeApplier(isAuthorized: false)
        let service = UnreadAppIconBadgeService(
            logger: TestLogger(),
            feedRepository: harness.feedRepository,
            articleStateRepository: harness.articleStateRepository,
            appSettingsService: appSettingsService,
            badgeApplier: badgeApplier
        )

        await service.refreshBadgeCount()

        #expect(badgeApplier.appliedCounts.isEmpty)
    }

    @Test
    func refreshBadgeCountClearsBadgeWithoutAuthorizationWhenSettingIsDisabled() async throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let appSettingsService = try #require(harness.dependencies.appSettingsService)
        let feed = try #require(try harness.insertFeeds(urls: ["https://example.com/feed.xml"]).first)
        _ = try harness.insertArticle(
            feed: feed,
            externalID: "unread",
            url: "https://example.com/articles/unread",
            title: "Unread"
        )
        let badgeApplier = RecordingAppIconBadgeApplier(isAuthorized: false)
        let service = UnreadAppIconBadgeService(
            logger: TestLogger(),
            feedRepository: harness.feedRepository,
            articleStateRepository: harness.articleStateRepository,
            appSettingsService: appSettingsService,
            badgeApplier: badgeApplier
        )

        await service.refreshBadgeCount()

        #expect(badgeApplier.authorizationRequestCount == 0)
        #expect(badgeApplier.appliedCounts == [0])
    }
}

private final class RecordingAppIconBadgeApplier: AppIconBadgeApplying {
    private let isAuthorized: Bool
    private(set) var appliedCounts: [Int] = []
    private(set) var authorizationRequestCount = 0

    init(isAuthorized: Bool = true) {
        self.isAuthorized = isAuthorized
    }

    func ensureBadgeAuthorization() async throws -> Bool {
        authorizationRequestCount += 1
        return isAuthorized
    }

    func setBadgeCount(_ count: Int) async throws {
        appliedCounts.append(count)
    }
}
