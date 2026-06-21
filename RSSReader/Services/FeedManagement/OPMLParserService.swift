import Foundation

enum OPMLParserError: Error, Equatable {
    case emptyDocument
    case malformedXML(line: Int, column: Int, message: String)
    case unsupportedRootElement(String)
    case missingBody
}

struct OPMLDocumentDTO: Equatable, Sendable {
    let version: String?
    let title: String?
    let feeds: [OPMLFeedOutlineDTO]
    let ignoredOutlineCount: Int
}

struct OPMLFeedOutlineDTO: Equatable, Sendable {
    let folderPath: [String]
    let title: String?
    let text: String?
    let xmlURL: String
    let htmlURL: String?

    var displayTitle: String? {
        title ?? text
    }
}

enum OPMLParserService {
    static func parse(_ data: Data) throws -> OPMLDocumentDTO {
        let document: FeedXMLDocument

        do {
            document = try FeedParserService.parse(data)
        } catch FeedParserError.emptyDocument {
            throw OPMLParserError.emptyDocument
        } catch FeedParserError.malformedXML(let line, let column, let message) {
            throw OPMLParserError.malformedXML(line: line, column: column, message: message)
        }

        let root = document.rootElement
        guard root.name == "opml" else {
            throw OPMLParserError.unsupportedRootElement(root.name)
        }

        guard let body = root.firstChild(named: "body") else {
            throw OPMLParserError.missingBody
        }

        var collector = OPMLOutlineCollector()
        for outline in body.children(named: "outline") {
            collector.collect(outline, folderPath: [])
        }

        return OPMLDocumentDTO(
            version: root.normalizedAttribute("version"),
            title: root.firstChild(named: "head")?.firstChildText(named: "title"),
            feeds: collector.feeds,
            ignoredOutlineCount: collector.ignoredOutlineCount
        )
    }
}

private struct OPMLOutlineCollector {
    private(set) var feeds: [OPMLFeedOutlineDTO] = []
    private(set) var ignoredOutlineCount = 0

    mutating func collect(_ outline: FeedXMLElement, folderPath: [String]) {
        if let xmlURL = outline.normalizedAttribute("xmlUrl") {
            feeds.append(
                OPMLFeedOutlineDTO(
                    folderPath: folderPath,
                    title: outline.normalizedAttribute("title"),
                    text: outline.normalizedAttribute("text"),
                    xmlURL: xmlURL,
                    htmlURL: outline.normalizedAttribute("htmlUrl")
                )
            )

            return
        }

        let childOutlines = outline.children(named: "outline")
        guard childOutlines.isEmpty == false else {
            ignoredOutlineCount += 1
            return
        }

        let nestedFolderPath = folderName(from: outline)
            .map { folderPath + [$0] }
            ?? folderPath

        for childOutline in childOutlines {
            collect(childOutline, folderPath: nestedFolderPath)
        }
    }

    private func folderName(from outline: FeedXMLElement) -> String? {
        outline.normalizedAttribute("title") ?? outline.normalizedAttribute("text")
    }
}

private extension FeedXMLElement {
    func normalizedAttribute(_ name: String) -> String? {
        guard let value = attributes[name]?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return nil
        }

        return value.isEmpty ? nil : value
    }
}
