import Foundation

nonisolated struct XMLParserStructuralPolicy: Equatable, Sendable {
    nonisolated enum MaterializedEntryKind: Equatable, Sendable {
        case feed
        case opml
    }

    let budget: RuntimeXMLInputBudget
    let materializedEntryKind: MaterializedEntryKind

    static let feed = XMLParserStructuralPolicy(
        budget: AppComposition.resourceBudgetContract.feedXML,
        materializedEntryKind: .feed
    )

    static let opml = XMLParserStructuralPolicy(
        budget: AppComposition.resourceBudgetContract.opml,
        materializedEntryKind: .opml
    )
}

extension FeedParserService {
    nonisolated static func parse(
        _ data: Data,
        structuralPolicy: XMLParserStructuralPolicy = .feed
    ) throws -> FeedXMLDocument {
        let isWhitespaceOnly = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .isEmpty == true

        if data.isEmpty || isWhitespaceOnly {
            throw FeedParserError.emptyDocument
        }

        let builder = FeedXMLTreeBuilder(structuralPolicy: structuralPolicy)
        let parser = XMLParser(data: data)
        parser.delegate = builder
        parser.shouldProcessNamespaces = true
        parser.shouldReportNamespacePrefixes = true

        let didParseSuccessfully = parser.parse()
        if didParseSuccessfully, let document = builder.document {
            return document
        }

        if builder.wasCancelled {
            throw CancellationError()
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

    nonisolated static func parse(_ response: FeedResponse) throws -> FeedXMLDocument {
        try parse(response.body)
    }
}

private nonisolated final class FeedXMLTreeBuilder: NSObject, XMLParserDelegate {
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
    private let structuralPolicy: XMLParserStructuralPolicy
    private var elementCount = 0
    private var materializedEntryCount = 0
    private(set) var document: FeedXMLDocument?
    private(set) var error: FeedParserError?
    private(set) var wasCancelled = false

    init(structuralPolicy: XMLParserStructuralPolicy) {
        self.structuralPolicy = structuralPolicy
    }

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes attributeDict: [String : String] = [:]
    ) {
        guard abortIfCancelled(parser) == false else { return }

        let resolvedName = elementName.isEmpty == false ? elementName : (qName ?? "")
        let nextElementCount = elementCount + 1
        let nextDepth = stack.count + 1
        let isMaterializedEntry = isMaterializedEntry(
            named: resolvedName,
            attributes: attributeDict
        )
        let nextMaterializedEntryCount = materializedEntryCount + (isMaterializedEntry ? 1 : 0)

        do {
            try structuralPolicy.budget.validateElementCount(nextElementCount)
            try structuralPolicy.budget.validateDepth(nextDepth)
            if isMaterializedEntry {
                try structuralPolicy.budget.validateEntryCount(nextMaterializedEntryCount)
            }
        } catch let violation as AppResourceBudgetViolation {
            error = .resourceLimitExceeded(violation)
            parser.abortParsing()
            return
        } catch {
            assertionFailure("Unexpected XML structural policy failure: \(error)")
            parser.abortParsing()
            return
        }

        elementCount = nextElementCount
        materializedEntryCount = nextMaterializedEntryCount
        let node = Node(
            name: resolvedName,
            qualifiedName: qName,
            namespaceURI: namespaceURI,
            attributes: attributeDict
        )
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard abortIfCancelled(parser) == false else { return }
        guard stack.isEmpty == false else { return }
        stack[stack.count - 1].textFragments.append(string)
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard abortIfCancelled(parser) == false else { return }
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
        guard wasCancelled == false, error == nil else { return }
        error = FeedParserError.malformedXML(
            line: parser.lineNumber,
            column: parser.columnNumber,
            message: parseError.localizedDescription
        )
    }

    func parser(_ parser: XMLParser, validationErrorOccurred validationError: any Error) {
        guard wasCancelled == false, error == nil else { return }
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

    private func isMaterializedEntry(
        named elementName: String,
        attributes: [String: String]
    ) -> Bool {
        let normalizedName = elementName.lowercased()
        let ancestorNames = stack.map { $0.name.lowercased() }

        switch structuralPolicy.materializedEntryKind {
        case .feed:
            return (ancestorNames == ["rss", "channel"] && normalizedName == "item")
                || (ancestorNames == ["feed"] && normalizedName == "entry")
        case .opml:
            guard normalizedName == "outline",
                  ancestorNames.count >= 2,
                  ancestorNames[0] == "opml",
                  ancestorNames[1] == "body",
                  ancestorNames.dropFirst(2).allSatisfy({ $0 == "outline" }),
                  stack.dropFirst(2).contains(where: hasFeedURL) == false else {
                return false
            }

            return normalizedFeedURL(in: attributes) != nil
        }
    }

    private func abortIfCancelled(_ parser: XMLParser) -> Bool {
        guard Task.isCancelled else { return false }
        wasCancelled = true
        parser.abortParsing()
        return true
    }

    private func hasFeedURL(_ node: Node) -> Bool {
        normalizedFeedURL(in: node.attributes) != nil
    }

    private func normalizedFeedURL(in attributes: [String: String]) -> String? {
        guard let value = attributes["xmlUrl"]?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              value.isEmpty == false else {
            return nil
        }

        return value
    }
}
