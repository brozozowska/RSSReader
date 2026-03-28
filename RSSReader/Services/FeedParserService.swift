import Foundation

enum FeedParserError: Error {
    case emptyDocument
    case malformedXML(line: Int, column: Int, message: String)
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
