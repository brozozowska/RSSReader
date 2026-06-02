import Foundation

extension FeedParserService {
    static func parseAtom(_ document: FeedXMLDocument) throws -> ParsedFeedDTO {
        let kind = detectFeedKind(in: document)
        guard kind == .atom else {
            throw FeedParserError.unsupportedFeedKind(kind)
        }

        let feedElement = document.rootElement
        guard feedElement.name.lowercased() == "feed" else {
            throw FeedParserError.missingAtomElement("feed")
        }

        let metadata = try extractAtomMetadata(from: document)
        let entries = try extractAtomArticlePayloads(from: document)

        return ParsedFeedDTO(
            kind: .atom,
            metadata: metadata,
            entries: entries
        )
    }

    static func parseAtom(_ response: FeedResponse) throws -> ParsedFeedDTO {
        try parseAtom(parse(response))
    }

    static func extractAtomMetadata(from document: FeedXMLDocument) throws -> ParsedFeedMetadataDTO {
        let feedElement = document.rootElement
        guard feedElement.name.lowercased() == "feed" else {
            throw FeedParserError.missingAtomElement("feed")
        }

        return ParsedFeedMetadataDTO(
            title: feedElement.firstChildText(named: "title"),
            subtitle: feedElement.firstChildText(named: "subtitle"),
            siteURL: atomLink(in: feedElement, rel: "alternate") ?? atomLink(in: feedElement),
            iconURL: feedElement.firstChildText(named: "icon") ?? feedElement.firstChildText(named: "logo"),
            language: feedElement.attributes["xml:lang"] ?? feedElement.attributes["lang"]
        )
    }

    static func extractAtomArticlePayloads(from document: FeedXMLDocument) throws -> [ParsedFeedEntryDTO] {
        let feedElement = document.rootElement
        guard feedElement.name.lowercased() == "feed" else {
            throw FeedParserError.missingAtomElement("feed")
        }

        let feedAuthor = atomAuthor(in: feedElement)
        return feedElement.children(named: "entry").map { entryElement in
            ParsedFeedEntryDTO(
                guid: entryElement.firstChildText(named: "id"),
                url: atomLink(in: entryElement, rel: "alternate") ?? atomLink(in: entryElement),
                canonicalURL: atomLink(in: entryElement, rel: "self"),
                title: entryElement.firstChildText(named: "title"),
                summary: entryElement.firstChildText(named: "summary"),
                contentHTML: atomContent(in: entryElement),
                contentText: entryElement.firstChildText(named: "content")
                    ?? entryElement.firstChildText(named: "summary"),
                author: atomAuthor(in: entryElement) ?? feedAuthor,
                publishedAtRaw: entryElement.firstChildText(named: "published"),
                updatedAtRaw: entryElement.firstChildText(named: "updated"),
                imageURL: atomLink(in: entryElement, rel: "enclosure")
            )
        }
    }

    private static func atomLink(in element: FeedXMLElement, rel: String? = nil) -> String? {
        let links = element.children(named: "link")
        let matchingLink = links.first { link in
            let linkRel = link.attributes["rel"]?.lowercased()

            if let rel {
                return linkRel == rel.lowercased()
            }

            return linkRel == nil || linkRel == "alternate"
        }

        return matchingLink?.attributes["href"]?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func atomAuthor(in element: FeedXMLElement) -> String? {
        element.nestedChildText(["author", "name"])
            ?? element.firstChildText(named: "author")
    }

    private static func atomContent(in element: FeedXMLElement) -> String? {
        element.firstChildText(named: "content")
            ?? element.firstChildText(named: "summary")
    }
}
