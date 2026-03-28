import Foundation

enum FeedParserError: Error {
    case emptyDocument
    case malformedXML(line: Int, column: Int, message: String)
    case unsupportedFeedKind(FeedKind)
    case missingRSSElement(String)
    case missingAtomElement(String)
}

struct FeedXMLDocument: Sendable {
    let rootElement: FeedXMLElement

    var detectedFeedKind: FeedKind {
        FeedParserService.detectFeedKind(in: self)
    }
}

struct FeedXMLElement: Sendable {
    let name: String
    let qualifiedName: String?
    let namespaceURI: String?
    let attributes: [String: String]
    let children: [FeedXMLElement]
    let text: String

    var normalizedText: String? {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    func firstChild(named name: String) -> FeedXMLElement? {
        children.first { $0.name == name }
    }

    func children(named name: String) -> [FeedXMLElement] {
        children.filter { $0.name == name }
    }

    func firstChildText(named name: String) -> String? {
        firstChild(named: name)?.normalizedText
    }

    func nestedChildText(_ path: [String]) -> String? {
        var currentElement: FeedXMLElement? = self

        for name in path {
            currentElement = currentElement?.firstChild(named: name)
        }

        return currentElement?.normalizedText
    }
}

struct ParsedFeedDTO: Sendable {
    let kind: FeedKind
    let metadata: ParsedFeedMetadataDTO
    let entries: [ParsedFeedEntryDTO]
}

struct ParsedFeedMetadataDTO: Sendable {
    let title: String?
    let subtitle: String?
    let siteURL: String?
    let iconURL: String?
    let language: String?

    init(
        title: String? = nil,
        subtitle: String? = nil,
        siteURL: String? = nil,
        iconURL: String? = nil,
        language: String? = nil
    ) {
        self.title = title
        self.subtitle = subtitle
        self.siteURL = siteURL
        self.iconURL = iconURL
        self.language = language
    }
}

struct ParsedFeedEntryDTO: Sendable {
    let guid: String?
    let url: String?
    let canonicalURL: String?
    let title: String?
    let summary: String?
    let contentHTML: String?
    let contentText: String?
    let author: String?
    let publishedAtRaw: String?
    let updatedAtRaw: String?
    let imageURL: String?

    init(
        guid: String? = nil,
        url: String? = nil,
        canonicalURL: String? = nil,
        title: String? = nil,
        summary: String? = nil,
        contentHTML: String? = nil,
        contentText: String? = nil,
        author: String? = nil,
        publishedAtRaw: String? = nil,
        updatedAtRaw: String? = nil,
        imageURL: String? = nil
    ) {
        self.guid = guid
        self.url = url
        self.canonicalURL = canonicalURL
        self.title = title
        self.summary = summary
        self.contentHTML = contentHTML
        self.contentText = contentText
        self.author = author
        self.publishedAtRaw = publishedAtRaw
        self.updatedAtRaw = updatedAtRaw
        self.imageURL = imageURL
    }
}

enum FeedParserService {
    static func parse(_ data: Data) throws -> FeedXMLDocument {
        let builder = FeedXMLTreeBuilder()
        let parser = XMLParser(data: data)
        parser.delegate = builder
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true

        let didParseSuccessfully = parser.parse()
        if didParseSuccessfully, let document = builder.document {
            return document
        }

        if let error = builder.error {
            throw error
        }

        let parserError = parser.parserError
        throw FeedParserError.malformedXML(
            line: parser.lineNumber,
            column: parser.columnNumber,
            message: parserError?.localizedDescription ?? "Unknown XML parsing error"
        )
    }

    static func parse(_ response: FeedResponse) throws -> FeedXMLDocument {
        try parse(response.body)
    }

    static func detectFeedKind(in document: FeedXMLDocument) -> FeedKind {
        let rootElement = document.rootElement
        let rootName = rootElement.name.lowercased()
        let qualifiedName = rootElement.qualifiedName?.lowercased()
        let namespaceURI = rootElement.namespaceURI?.lowercased()

        if rootName == "rss" {
            return .rss
        }

        let isAtomFeedByName = rootName == "feed" || qualifiedName == "atom:feed"
        let isAtomFeedByNamespace = namespaceURI == "http://www.w3.org/2005/atom"

        if isAtomFeedByName && isAtomFeedByNamespace {
            return .atom
        }

        return .unknown
    }

    static func detectFeedKind(in response: FeedResponse) throws -> FeedKind {
        try detectFeedKind(in: parse(response))
    }

    static func parseRSS(_ document: FeedXMLDocument) throws -> ParsedFeedDTO {
        let kind = detectFeedKind(in: document)
        guard kind == .rss else {
            throw FeedParserError.unsupportedFeedKind(kind)
        }

        let rootElement = document.rootElement
        guard let channelElement = rootElement.firstChild(named: "channel") else {
            throw FeedParserError.missingRSSElement("channel")
        }

        let metadata = ParsedFeedMetadataDTO(
            title: channelElement.firstChildText(named: "title"),
            subtitle: channelElement.firstChildText(named: "description"),
            siteURL: channelElement.firstChildText(named: "link"),
            iconURL: channelElement.nestedChildText(["image", "url"]),
            language: channelElement.firstChildText(named: "language")
        )

        let entries = channelElement.children(named: "item").map { itemElement in
            ParsedFeedEntryDTO(
                guid: itemElement.firstChildText(named: "guid"),
                url: itemElement.firstChildText(named: "link"),
                canonicalURL: itemElement.firstChildText(named: "comments"),
                title: itemElement.firstChildText(named: "title"),
                summary: itemElement.firstChildText(named: "description"),
                contentHTML: contentHTML(in: itemElement),
                contentText: itemElement.firstChildText(named: "description"),
                author: itemElement.firstChildText(named: "author")
                    ?? itemElement.firstChildText(named: "dc:creator")
                    ?? itemElement.firstChildText(named: "creator"),
                publishedAtRaw: itemElement.firstChildText(named: "pubDate"),
                updatedAtRaw: itemElement.firstChildText(named: "dc:date"),
                imageURL: enclosureURL(in: itemElement)
            )
        }

        return ParsedFeedDTO(
            kind: .rss,
            metadata: metadata,
            entries: entries
        )
    }

    static func parseRSS(_ response: FeedResponse) throws -> ParsedFeedDTO {
        try parseRSS(parse(response))
    }

    static func parseAtom(_ document: FeedXMLDocument) throws -> ParsedFeedDTO {
        let kind = detectFeedKind(in: document)
        guard kind == .atom else {
            throw FeedParserError.unsupportedFeedKind(kind)
        }

        let feedElement = document.rootElement
        guard feedElement.name.lowercased() == "feed" else {
            throw FeedParserError.missingAtomElement("feed")
        }

        let metadata = ParsedFeedMetadataDTO(
            title: feedElement.firstChildText(named: "title"),
            subtitle: feedElement.firstChildText(named: "subtitle"),
            siteURL: atomLink(in: feedElement, rel: "alternate") ?? atomLink(in: feedElement),
            iconURL: feedElement.firstChildText(named: "icon") ?? feedElement.firstChildText(named: "logo"),
            language: feedElement.attributes["xml:lang"] ?? feedElement.attributes["lang"]
        )

        let feedAuthor = atomAuthor(in: feedElement)
        let entries = feedElement.children(named: "entry").map { entryElement in
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

        return ParsedFeedDTO(
            kind: .atom,
            metadata: metadata,
            entries: entries
        )
    }

    static func parseAtom(_ response: FeedResponse) throws -> ParsedFeedDTO {
        try parseAtom(parse(response))
    }

    private static func contentHTML(in itemElement: FeedXMLElement) -> String? {
        itemElement.firstChildText(named: "content:encoded")
            ?? itemElement.firstChildText(named: "encoded")
    }

    private static func enclosureURL(in itemElement: FeedXMLElement) -> String? {
        guard let enclosure = itemElement.firstChild(named: "enclosure") else { return nil }
        return enclosure.attributes["url"]?.trimmingCharacters(in: .whitespacesAndNewlines)
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

private final class FeedXMLTreeBuilder: NSObject, XMLParserDelegate {
    private final class Node {
        let name: String
        let qualifiedName: String?
        let namespaceURI: String?
        let attributes: [String: String]
        var children: [FeedXMLElement] = []
        var textFragments: [String] = []

        init(
            name: String,
            qualifiedName: String?,
            namespaceURI: String?,
            attributes: [String: String]
        ) {
            self.name = name
            self.qualifiedName = qualifiedName
            self.namespaceURI = namespaceURI
            self.attributes = attributes
        }

        func build() -> FeedXMLElement {
            FeedXMLElement(
                name: name,
                qualifiedName: qualifiedName,
                namespaceURI: namespaceURI,
                attributes: attributes,
                children: children,
                text: textFragments.joined()
            )
        }
    }

    private var stack: [Node] = []
    private(set) var document: FeedXMLDocument?
    private(set) var error: FeedParserError?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        let resolvedName = elementName.isEmpty == false ? elementName : (qName ?? "")
        let node = Node(
            name: resolvedName,
            qualifiedName: qName,
            namespaceURI: namespaceURI,
            attributes: attributeDict
        )
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard stack.isEmpty == false else { return }
        stack[stack.count - 1].textFragments.append(string)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard stack.isEmpty == false else { return }
        guard let value = String(data: CDATABlock, encoding: .utf8) else { return }
        stack[stack.count - 1].textFragments.append(value)
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard let node = stack.popLast() else { return }
        let element = node.build()

        if stack.isEmpty {
            document = FeedXMLDocument(rootElement: element)
        } else {
            stack[stack.count - 1].children.append(element)
        }
    }

    func parser(_ parser: XMLParser, parseErrorOccurred parseError: any Error) {
        error = FeedParserError.malformedXML(
            line: parser.lineNumber,
            column: parser.columnNumber,
            message: parseError.localizedDescription
        )
    }

    func parser(_ parser: XMLParser, validationErrorOccurred validationError: any Error) {
        error = FeedParserError.malformedXML(
            line: parser.lineNumber,
            column: parser.columnNumber,
            message: validationError.localizedDescription
        )
    }

    func parserDidEndDocument(_ parser: XMLParser) {
        if document == nil, error == nil {
            error = .emptyDocument
        }
    }
}
