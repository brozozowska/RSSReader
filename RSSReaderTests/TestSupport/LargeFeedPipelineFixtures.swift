import Foundation
@testable import RSSReader

nonisolated enum LargeFeedPipelineTestContract {
    static let uniqueEntryCount = 750
    static let duplicateEntryCount = 100
    static let rejectedEntryCount = 50
    static let rawEntryCount = uniqueEntryCount + duplicateEntryCount + rejectedEntryCount
    static let maximumEstimatedWorkingSetBytes = 2 * 1024 * 1024
    static let maximumRefreshDuration: Duration = .seconds(10)
    static let maximumMainActorHeartbeatWait: TimeInterval = 5
}

nonisolated struct LargeFeedPipelineFixture: Sendable {
    let feedURL: URL
    let body: String
    let rawEntryCount: Int
    let expectedAcceptedEntryCount: Int
    let expectedRejectedEntryCount: Int
    let estimatedWorkingSetByteCount: Int

    var bodyByteCount: Int {
        body.utf8.count
    }

    static func make() -> LargeFeedPipelineFixture {
        let feedURL = URL(string: "https://example.com/large-feed.xml")!
        var itemXML: [String] = []
        itemXML.reserveCapacity(LargeFeedPipelineTestContract.rawEntryCount)

        for index in 0..<LargeFeedPipelineTestContract.uniqueEntryCount {
            itemXML.append(validItemXML(index: index, isDuplicate: false))
        }

        for index in 0..<LargeFeedPipelineTestContract.duplicateEntryCount {
            itemXML.append(validItemXML(index: index, isDuplicate: true))
        }

        for index in 0..<LargeFeedPipelineTestContract.rejectedEntryCount {
            itemXML.append(
                """
                <item>
                  <description>Rejected deterministic entry \(index)</description>
                </item>
                """
            )
        }

        let joinedItemXML = itemXML.joined(separator: "\n")
        let body = """
        <?xml version="1.0" encoding="UTF-8"?>
        <rss version="2.0">
          <channel>
            <title>Large Deterministic Feed</title>
            <link>https://example.com/large/</link>
            <description>Large feed pipeline fixture</description>
            <language>en</language>
            \(joinedItemXML)
          </channel>
        </rss>
        """
        let materializedItemTextByteCount = itemXML.reduce(into: 0) { byteCount, item in
            byteCount += item.utf8.count
        }

        return LargeFeedPipelineFixture(
            feedURL: feedURL,
            body: body,
            rawEntryCount: itemXML.count,
            expectedAcceptedEntryCount: LargeFeedPipelineTestContract.uniqueEntryCount,
            expectedRejectedEntryCount: LargeFeedPipelineTestContract.rejectedEntryCount,
            estimatedWorkingSetByteCount: body.utf8.count + materializedItemTextByteCount
        )
    }

    @MainActor
    func makeResponse(feedID: UUID = UUID()) -> FeedResponse {
        FeedResponse(
            request: FeedRequest(feedID: feedID, url: feedURL),
            sourceURL: feedURL,
            statusCode: 200,
            headers: ["Content-Type": "application/rss+xml; charset=utf-8"],
            body: Data(body.utf8)
        )
    }

    private static func validItemXML(index: Int, isDuplicate: Bool) -> String {
        let titleSuffix = isDuplicate ? " enriched duplicate" : ""
        let summarySuffix = isDuplicate
            ? " with richer deterministic duplicate content"
            : ""

        return """
        <item>
          <title>Large Article \(index)\(titleSuffix)</title>
          <link>https://example.com/large/articles/\(index)</link>
          <guid isPermaLink="false">large-article-\(index)</guid>
          <description>Deterministic summary \(index)\(summarySuffix)</description>
          <pubDate>Tue, 02 Jan 2024 10:00:00 GMT</pubDate>
        </item>
        """
    }
}
