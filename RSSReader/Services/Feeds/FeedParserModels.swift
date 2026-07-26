import Foundation

nonisolated enum FeedParserError: Error {
    case emptyDocument
    case malformedXML(line: Int, column: Int, message: String)
    case resourceLimitExceeded(AppResourceBudgetViolation)
    case unsupportedFeedKind(FeedKind)
    case missingRSSElement(String)
    case missingAtomElement(String)
}

nonisolated struct FeedXMLDocument: Sendable {
    let rootElement: FeedXMLElement

    var detectedFeedKind: FeedKind {
        FeedParserService.detectFeedKind(in: self)
    }
}

nonisolated struct FeedXMLElement: Sendable {
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

nonisolated struct ParsedFeedDTO: Sendable {
    let kind: FeedKind
    let metadata: ParsedFeedMetadataDTO
    let entries: [ParsedFeedEntryDTO]
}

nonisolated struct ParsedFeedMetadataDTO: Sendable {
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

nonisolated struct ParsedFeedEntryDTO: Sendable {
    let externalID: String?
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
    let publishedAt: Date?
    let updatedAt: Date?
    let imageURL: String?

    init(
        externalID: String? = nil,
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
        publishedAt: Date? = nil,
        updatedAt: Date? = nil,
        imageURL: String? = nil
    ) {
        self.externalID = externalID
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
        self.publishedAt = publishedAt
        self.updatedAt = updatedAt
        self.imageURL = imageURL
    }
}
