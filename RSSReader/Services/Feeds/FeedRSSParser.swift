import Foundation

extension FeedParserService {
    nonisolated static func parseRSS(_ document: FeedXMLDocument) throws -> ParsedFeedDTO {
        let kind = detectFeedKind(in: document)
        guard kind == .rss else {
            throw FeedParserError.unsupportedFeedKind(kind)
        }

        guard document.rootElement.firstChild(named: "channel") != nil else {
            throw FeedParserError.missingRSSElement("channel")
        }

        let metadata = try extractRSSMetadata(from: document)
        let entries = try extractRSSArticlePayloads(from: document)

        return ParsedFeedDTO(
            kind: .rss,
            metadata: metadata,
            entries: entries
        )
    }

    nonisolated static func parseRSS(_ response: FeedResponse) throws -> ParsedFeedDTO {
        try parseRSS(parse(response))
    }

    nonisolated static func extractRSSMetadata(from document: FeedXMLDocument) throws -> ParsedFeedMetadataDTO {
        guard let channelElement = document.rootElement.firstChild(named: "channel") else {
            throw FeedParserError.missingRSSElement("channel")
        }

        return ParsedFeedMetadataDTO(
            title: channelElement.firstChildText(named: "title"),
            subtitle: channelElement.firstChildText(named: "description"),
            siteURL: channelElement.firstChildText(named: "link"),
            iconURL: channelElement.nestedChildText(["image", "url"]),
            language: channelElement.firstChildText(named: "language")
        )
    }

    nonisolated static func extractRSSArticlePayloads(
        from document: FeedXMLDocument
    ) throws -> [ParsedFeedEntryDTO] {
        guard let channelElement = document.rootElement.firstChild(named: "channel") else {
            throw FeedParserError.missingRSSElement("channel")
        }

        return channelElement.children(named: "item").map { itemElement in
            ParsedFeedEntryDTO(
                guid: itemElement.firstChildText(named: "guid"),
                url: itemElement.firstChildText(named: "link"),
                canonicalURL: itemElement.firstChildText(named: "comments"),
                title: itemElement.firstChildText(named: "title"),
                summary: itemElement.firstChildText(named: "description"),
                contentHTML: rssContentHTML(in: itemElement),
                contentText: itemElement.firstChildText(named: "description"),
                author: itemElement.firstChildText(named: "author")
                    ?? itemElement.firstChildText(named: "dc:creator")
                    ?? itemElement.firstChildText(named: "creator"),
                publishedAtRaw: itemElement.firstChildText(named: "pubDate"),
                updatedAtRaw: itemElement.firstChildText(named: "dc:date")
                    ?? itemElement.firstChildText(named: "date"),
                imageURL: rssEnclosureURL(in: itemElement)
            )
        }
    }

    nonisolated private static func rssContentHTML(in itemElement: FeedXMLElement) -> String? {
        itemElement.firstChildText(named: "content:encoded")
            ?? itemElement.firstChildText(named: "encoded")
    }

    nonisolated private static func rssEnclosureURL(in itemElement: FeedXMLElement) -> String? {
        guard let enclosure = itemElement.firstChild(named: "enclosure") else { return nil }
        return enclosure.attributes["url"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
