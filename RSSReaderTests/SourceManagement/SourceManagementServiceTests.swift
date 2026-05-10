import Foundation
import Testing
@testable import RSSReader

@Suite("Source Management / Services")
@MainActor
struct SourceManagementServiceTests {
    @Test
    func sourceManagementServicePreviewsFeedMetadataThroughFetcherAndParser() async throws {
        let feedURL = "https://example.com/source-management-preview.xml"
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
        let service = try #require(harness.dependencies.sourceManagementService)

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
    func sourceManagementServiceDiscoversCommonRSSPathFromSiteURL() async throws {
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
        let service = try #require(harness.dependencies.sourceManagementService)

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
    func sourceManagementServiceDiscoversFeedFromHTMLAlternateLink() async throws {
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
        let service = try #require(harness.dependencies.sourceManagementService)

        let preview = try await service.previewFeed(urlString: "example.com")
        let requests = await harness.httpClient.recordedRequests().map(\.url.absoluteString)

        #expect(preview.requestedURL == discoveredFeedURL)
        #expect(preview.resolvedFeedURL == discoveredFeedURL)
        #expect(preview.title == "HTML Linked Feed")
        #expect(requests.contains(siteURL))
        #expect(requests.contains(discoveredFeedURL))
    }

    @Test
    func sourceManagementServiceCreatesFolderWithNextSortOrder() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let service = try #require(harness.dependencies.sourceManagementService)

        let firstFolder = try service.createFolder(
            SourceManagementCreateFolderCommand(name: "News")
        )
        let secondFolder = try service.createFolder(
            SourceManagementCreateFolderCommand(name: "Tech")
        )

        let folders = try harness.folderRepository.fetchAllFolders()

        #expect(firstFolder.sortOrder == 0)
        #expect(secondFolder.sortOrder == 1)
        #expect(folders.map(\.name) == ["News", "Tech"])
        #expect(folders.map(\.sortOrder) == [0, 1])
    }

    @Test
    func sourceManagementServiceCreatesAndMovesFeedWithoutScreenLevelPersistenceAccess() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let service = try #require(harness.dependencies.sourceManagementService)
        let techFolder = try service.createFolder(SourceManagementCreateFolderCommand(name: "Tech"))
        let newsFolder = try service.createFolder(SourceManagementCreateFolderCommand(name: "News"))
        let preview = SourceManagementFeedPreview(
            requestedURL: "https://example.com/feed.xml",
            resolvedFeedURL: "https://example.com/feed.xml",
            title: "Example Feed",
            subtitle: "Source management preview",
            siteURL: "https://example.com/",
            iconURL: "https://example.com/icon.png",
            language: "en",
            kind: .rss,
            parserAnomalyCount: 0,
            rejectedEntryCount: 0,
            existingFeedID: nil
        )

        let createdFeed = try service.createFeed(
            SourceManagementCreateFeedCommand(
                preview: preview,
                folderPlacement: .folder(techFolder.id)
            )
        )
        let createdPersistedFeed = try harness.feedRepository.fetchFeed(id: createdFeed.id)
        var persistedFeed = try #require(createdPersistedFeed)
        #expect(persistedFeed.folder?.name == "Tech")

        let movedFeed = try service.moveFeed(
            SourceManagementMoveFeedCommand(
                feedID: createdFeed.id,
                folderPlacement: .folder(newsFolder.id)
            )
        )
        #expect(movedFeed.folderName == "News")

        let movedPersistedFeed = try harness.feedRepository.fetchFeed(id: createdFeed.id)
        persistedFeed = try #require(movedPersistedFeed)
        #expect(persistedFeed.folder?.name == "News")

        let ungroupedFeed = try service.moveFeed(
            SourceManagementMoveFeedCommand(
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
    func sourceManagementServiceBuildsFolderFeedCountsWithoutFolderOwnedFeedCollection() throws {
        let harness = try TestHarness.make(httpClient: ScriptedHTTPClient())
        let service = try #require(harness.dependencies.sourceManagementService)
        let newsFolder = try service.createFolder(SourceManagementCreateFolderCommand(name: "News"))
        let techFolder = try service.createFolder(SourceManagementCreateFolderCommand(name: "Tech"))
        let preview = SourceManagementFeedPreview(
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
            SourceManagementCreateFeedCommand(
                preview: preview,
                folderPlacement: .folder(newsFolder.id)
            )
        )

        let groupedFolders = try service.fetchFolders()
        #expect(groupedFolders.first(where: { $0.id == newsFolder.id })?.feedCount == 1)
        #expect(groupedFolders.first(where: { $0.id == techFolder.id })?.feedCount == 0)
    }
}
