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
            let publishedAtRaw = itemElement.firstChildText(named: "pubDate")
                ?? dublinCoreTermsText(named: "created", in: itemElement)
                ?? dublinCoreElementText(named: "date", in: itemElement)

            return ParsedFeedEntryDTO(
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
                publishedAtRaw: publishedAtRaw,
                updatedAtRaw: dublinCoreTermsText(named: "modified", in: itemElement),
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

    nonisolated private static func dublinCoreElementText(
        named name: String,
        in itemElement: FeedXMLElement
    ) -> String? {
        firstChildText(
            named: name,
            namespaceURIs: [
                "http://purl.org/dc/elements/1.1/",
                "https://purl.org/dc/elements/1.1/"
            ],
            in: itemElement
        )
    }

    nonisolated private static func dublinCoreTermsText(
        named name: String,
        in itemElement: FeedXMLElement
    ) -> String? {
        firstChildText(
            named: name,
            namespaceURIs: [
                "http://purl.org/dc/terms/",
                "https://purl.org/dc/terms/"
            ],
            in: itemElement
        )
    }

    nonisolated private static func firstChildText(
        named name: String,
        namespaceURIs: Set<String>,
        in itemElement: FeedXMLElement
    ) -> String? {
        itemElement.children.first {
            $0.name == name && $0.namespaceURI.map(namespaceURIs.contains) == true
        }?.normalizedText
    }
}
