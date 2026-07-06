import Foundation
import Testing
@testable import RSSReader

@Suite("Feed Management / Services")
@MainActor
struct FeedManagementServiceTests {
    @Test
    func feedManagementServicePreviewsFeedMetadataThroughFetcherAndParser() async throws {
        let feedURL = "https://example.com/feed-management-preview.xml"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    feedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: makeValidRSSFeedXML(
                            channelTitle: "Preview Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: "Preview Article",
                            itemLink: "https://example.com/articles/preview",
                            itemGUID: "preview-article",
                            itemDescription: "Preview description",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        let service = try #require(harness.dependencies.feedManagementService)

        let preview = try await service.previewFeed(urlString: feedURL)

        #expect(preview.requestedURL == feedURL)
        #expect(preview.resolvedFeedURL == feedURL)
        #expect(preview.title == "Preview Feed")
        #expect(preview.siteURL == "https://example.com/")
        #expect(preview.kind == .rss)
        #expect(preview.existingFeedID == nil)
        #expect(preview.rejectedEntryCount == 0)
    }

    @Test
    func feedManagementServiceDiscoversCommonRSSPathFromSiteURL() async throws {
        let discoveredFeedURL = "https://example.com/rss"
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    discoveredFeedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: makeValidRSSFeedXML(
                            channelTitle: "Discovered Common Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: "Common Feed Article",
                            itemLink: "https://example.com/articles/common",
                            itemGUID: "common-feed-article",
                            itemDescription: "Common feed description",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        let service = try #require(harness.dependencies.feedManagementService)

        let preview = try await service.previewFeed(urlString: "example.com")
        let requests = await harness.httpClient.recordedRequests()

        #expect(preview.requestedURL == discoveredFeedURL)
        #expect(preview.resolvedFeedURL == discoveredFeedURL)
        #expect(preview.title == "Discovered Common Feed")
        #expect(requests.map(\.url.absoluteString) == [
            "https://example.com/feed",
            discoveredFeedURL
        ])
    }

    @Test
    func feedManagementServiceDiscoversFeedFromHTMLAlternateLink() async throws {
        let siteURL = "https://example.com"
        let discoveredFeedURL = "https://example.com/custom-feed.xml"
        let html = """
        <!doctype html>
        <html>
          <head>
            <link rel="alternate" type="application/rss+xml" title="RSS" href="/custom-feed.xml">
          </head>
          <body>Example</body>
        </html>
        """
        let harness = try TestHarness.make(
            httpClient: ScriptedHTTPClient(
                responsesByURL: [
                    siteURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "text/html; charset=utf-8"],
                        body: html
                    ),
                    discoveredFeedURL: .response(
                        statusCode: 200,
                        headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
                        body: makeValidRSSFeedXML(
                            channelTitle: "HTML Linked Feed",
                            channelLink: "https://example.com/",
                            language: "en",
                            itemTitle: "HTML Linked Article",
                            itemLink: "https://example.com/articles/html-linked",
                            itemGUID: "html-linked-feed-article",
                            itemDescription: "HTML linked feed description",
                            pubDate: "Tue, 02 Jan 2024 10:00:00 GMT"
                        )
                    )
                ]
            )
        )
        let service = try #require(harness.dependencies.feedManagementService)

        let preview = try await service.previewFeed(urlString: "example.com")
        let requests = await harness.httpClient.recordedRequests().map(\.url.absoluteString)

        #expect(preview.requestedURL == discoveredFeedURL)
        #expect(preview.resolvedFeedURL == discoveredFeedURL)
        #expect(preview.title == "HTML Linked Feed")
        #expect(requests.contains(siteURL))
        #expect(requests.contains(discoveredFeedURL))
    }

    @Test
    func feedManagementServiceCreatesFolderWithNextSortOrder() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let service = try #require(harness.dependencies.feedManagementService)

        let firstFolder = try service.createFolder(
            FeedManagementCreateFolderCommand(name: "News")
        )
        let secondFolder = try service.createFolder(
            FeedManagementCreateFolderCommand(name: "Tech")
        )

        let folders = try harness.folderRepository.fetchAllFolders()

        #expect(firstFolder.sortOrder == 0)
        #expect(secondFolder.sortOrder == 1)
        #expect(folders.map(\.name) == ["News", "Tech"])
        #expect(folders.map(\.sortOrder) == [0, 1])
    }

    @Test
    func feedManagementServiceRejectsCaseInsensitiveDuplicateFolderNames() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let service = try #require(harness.dependencies.feedManagementService)

        let techFolder = try service.createFolder(FeedManagementCreateFolderCommand(name: "Tech"))
        let newsFolder = try service.createFolder(FeedManagementCreateFolderCommand(name: "News"))

        #expect(throws: FeedManagementServiceError.duplicateFolderName("TeCh")) {
            _ = try service.createFolder(FeedManagementCreateFolderCommand(name: " TeCh "))
        }

        #expect(throws: FeedManagementServiceError.duplicateFolderName("teCH")) {
            _ = try service.updateFolder(
                FeedManagementUpdateFolderCommand(
                    folderID: newsFolder.id,
                    name: " teCH "
                )
            )
        }

        let renamedSameFolder = try service.updateFolder(
            FeedManagementUpdateFolderCommand(
                folderID: techFolder.id,
                name: "TECH"
            )
        )

        #expect(renamedSameFolder.name == "TECH")
    }

    @Test
    func feedManagementServiceCreatesAndMovesFeedWithoutScreenLevelPersistenceAccess() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let service = try #require(harness.dependencies.feedManagementService)
        let techFolder = try service.createFolder(FeedManagementCreateFolderCommand(name: "Tech"))
        let newsFolder = try service.createFolder(FeedManagementCreateFolderCommand(name: "News"))
        let preview = FeedManagementFeedPreview(
            requestedURL: "https://example.com/feed.xml",
            resolvedFeedURL: "https://example.com/feed.xml",
            title: "Example Feed",
            subtitle: "Feed management preview",
            siteURL: "https://example.com/",
            iconURL: "https://example.com/icon.png",
            language: "en",
            kind: .rss,
            parserAnomalyCount: 0,
            rejectedEntryCount: 0,
            existingFeedID: nil
        )

        let createdFeed = try service.createFeed(
            FeedManagementCreateFeedCommand(
                preview: preview,
                folderPlacement: .folder(techFolder.id)
            )
        )
        let createdPersistedFeed = try harness.feedRepository.fetchFeed(id: createdFeed.id)
        var persistedFeed = try #require(createdPersistedFeed)
        #expect(persistedFeed.folder?.name == "Tech")
        #expect(persistedFeed.iconURL == nil)

        let movedFeed = try service.moveFeed(
            FeedManagementMoveFeedCommand(
                feedID: createdFeed.id,
                folderPlacement: .folder(newsFolder.id)
            )
        )
        #expect(movedFeed.folderName == "News")

        let movedPersistedFeed = try harness.feedRepository.fetchFeed(id: createdFeed.id)
        persistedFeed = try #require(movedPersistedFeed)
        #expect(persistedFeed.folder?.name == "News")

        let ungroupedFeed = try service.moveFeed(
            FeedManagementMoveFeedCommand(
                feedID: createdFeed.id,
                folderPlacement: .ungrouped
            )
        )
        #expect(ungroupedFeed.folderID == nil)
        #expect(ungroupedFeed.folderName == nil)

        let ungroupedPersistedFeed = try harness.feedRepository.fetchFeed(id: createdFeed.id)
        persistedFeed = try #require(ungroupedPersistedFeed)
        #expect(persistedFeed.folder == nil)
    }

    @Test
    func feedManagementServiceStoresDisplayTitleOverrideSeparatelyFromFeedMetadata() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let service = try #require(harness.dependencies.feedManagementService)
        let preview = FeedManagementFeedPreview(
            requestedURL: "https://example.com/feed.xml",
            resolvedFeedURL: "https://example.com/feed.xml",
            title: "XML Feed Title",
            subtitle: nil,
            siteURL: "https://example.com/",
            iconURL: nil,
            language: "en",
            kind: .rss,
            parserAnomalyCount: 0,
            rejectedEntryCount: 0,
            existingFeedID: nil
        )

        let createdFeed = try service.createFeed(
            FeedManagementCreateFeedCommand(
                preview: preview,
                displayTitleOverride: "My Feed",
                folderPlacement: .ungrouped
            )
        )

        let persistedFeed = try #require(try harness.feedRepository.fetchFeed(id: createdFeed.id))
        #expect(persistedFeed.title == "XML Feed Title")
        #expect(persistedFeed.displayTitleOverride == "My Feed")
        #expect(persistedFeed.displayTitle == "My Feed")
        #expect(createdFeed.title == "My Feed")
        #expect(createdFeed.metadataTitle == "XML Feed Title")

        let sidebarItem = try #require(try harness.feedRepository.fetchSidebarItems().first)
        #expect(sidebarItem.title == "My Feed")
    }

    @Test
    func feedManagementServiceUpdatesDisplayTitleWithoutPreviewWhenURLIsUnchanged() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let service = try #require(harness.dependencies.feedManagementService)
        let feed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/existing.xml"]).first
        )
        let article = try harness.insertArticle(
            feed: feed,
            externalID: "article-1",
            url: "https://example.com/articles/1",
            title: "Article One"
        )

        let updatedFeed = try service.updateFeed(
            FeedManagementUpdateFeedCommand(
                feedID: feed.id,
                displayTitleOverride: "Renamed Feed",
                folderPlacement: .ungrouped
            )
        )

        let persistedFeed = try #require(try harness.feedRepository.fetchFeed(id: feed.id))
        let projectedArticle = try #require(try harness.articleRepository.fetchArticle(id: article.id))
        #expect(persistedFeed.title == feed.title)
        #expect(persistedFeed.displayTitleOverride == "Renamed Feed")
        #expect(updatedFeed.title == "Renamed Feed")
        #expect(projectedArticle.feedTitle == "Renamed Feed")
    }

    @Test
    func feedManagementServiceRejectsDuplicateDisplayTitleOnCreateAndUpdate() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let service = try #require(harness.dependencies.feedManagementService)
        let existingFeed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/existing.xml"]).first
        )
        _ = try harness.feedRepository.updateDetails(
            for: existingFeed.id,
            with: FeedDetailsUpdate(displayTitleOverride: "Tech News")
        )
        let newFeedPreview = FeedManagementFeedPreview(
            requestedURL: "https://example.com/new.xml",
            resolvedFeedURL: "https://example.com/new.xml",
            title: "New XML Title",
            subtitle: nil,
            siteURL: "https://example.com/",
            iconURL: nil,
            language: "en",
            kind: .rss,
            parserAnomalyCount: 0,
            rejectedEntryCount: 0,
            existingFeedID: nil
        )

        #expect(throws: FeedManagementServiceError.duplicateFeedDisplayName("tech news")) {
            _ = try service.createFeed(
                FeedManagementCreateFeedCommand(
                    preview: newFeedPreview,
                    displayTitleOverride: " tech news ",
                    folderPlacement: .ungrouped
                )
            )
        }

        let otherFeed = try #require(
            try harness.insertFeeds(urls: ["https://example.com/other.xml"]).last
        )
        #expect(throws: FeedManagementServiceError.duplicateFeedDisplayName("TECH NEWS")) {
            _ = try service.updateFeed(
                FeedManagementUpdateFeedCommand(
                    feedID: otherFeed.id,
                    displayTitleOverride: "TECH NEWS",
                    folderPlacement: .ungrouped
                )
            )
        }
    }

    @Test
    func feedManagementServiceBuildsFolderFeedCountsWithoutFolderOwnedFeedCollection() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let service = try #require(harness.dependencies.feedManagementService)
        let newsFolder = try service.createFolder(FeedManagementCreateFolderCommand(name: "News"))
        let techFolder = try service.createFolder(FeedManagementCreateFolderCommand(name: "Tech"))
        let preview = FeedManagementFeedPreview(
            requestedURL: "https://example.com/grouped-feed.xml",
            resolvedFeedURL: "https://example.com/grouped-feed.xml",
            title: "Grouped Feed",
            subtitle: nil,
            siteURL: "https://example.com/",
            iconURL: nil,
            language: "en",
            kind: .rss,
            parserAnomalyCount: 0,
            rejectedEntryCount: 0,
            existingFeedID: nil
        )

        _ = try service.createFeed(
            FeedManagementCreateFeedCommand(
                preview: preview,
                folderPlacement: .folder(newsFolder.id)
            )
        )

        let groupedFolders = try service.fetchFolders()
        #expect(groupedFolders.first(where: { $0.id == newsFolder.id })?.feedCount == 1)
        #expect(groupedFolders.first(where: { $0.id == techFolder.id })?.feedCount == 0)
    }
}
