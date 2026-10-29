import Foundation

enum ArticleContentBodyBlock: Equatable, Sendable {
    case heading(level: Int, ArticleContentTextBlock)
    case paragraph(ArticleContentTextBlock)
    case list(ArticleContentListBlock)
    case definitionList(ArticleContentDefinitionListBlock)
    case table(ArticleContentTableBlock)
    indirect case disclosure(ArticleContentDisclosureBlock)
    indirect case aside([ArticleContentBodyBlock])
    indirect case figure([ArticleContentBodyBlock])
    case address(ArticleContentTextBlock)
    case blockquote([ArticleContentTextBlock])
    case codeBlock(String)
    case preformattedText(String)
    case divider
    case caption(ArticleContentTextBlock)
    case image(URL)
    case media(ArticleContentMediaBlock)
    case fallbackNotice(ArticleContentNotice)
}

struct ArticleContentMediaBlock: Equatable, Sendable {
    let kind: ArticleContentMediaKind
    let url: URL
}

enum ArticleContentMediaKind: Equatable, Sendable {
    case audio
    case video
    case knownEmbedded
    case embedded
    case generic
}

enum ArticleContentListKind: Equatable, Sendable {
    case ordered
    case unordered
}

struct ArticleContentListBlock: Equatable, Sendable {
    let kind: ArticleContentListKind
    let items: [ArticleContentTextBlock]
}

struct ArticleContentDefinitionListBlock: Equatable, Sendable {
    let entries: [ArticleContentDefinitionEntry]
}

struct ArticleContentDefinitionEntry: Identifiable, Sendable {
    let id = UUID()
    let term: ArticleContentTextBlock?
    let definitions: [ArticleContentTextBlock?]

    static func == (lhs: ArticleContentDefinitionEntry, rhs: ArticleContentDefinitionEntry) -> Bool {
        lhs.term == rhs.term && lhs.definitions == rhs.definitions
    }
}

extension ArticleContentDefinitionEntry: Equatable {}

struct ArticleContentDisclosureBlock: Equatable, Sendable {
    let summary: ArticleContentTextBlock
    let content: [ArticleContentBodyBlock]
    let isInitiallyExpanded: Bool
}

struct ArticleContentTableBlock: Equatable, Sendable {
    let columnHeaders: [ArticleContentTextBlock?]
    let headerSource: ArticleContentTableHeaderSource?
    let rows: [ArticleContentTableRow]
}

enum ArticleContentTableHeaderSource: Equatable, Sendable {
    case explicit
    case inferred
}

struct ArticleContentTableRow: Identifiable, Sendable {
    let id = UUID()
    let heading: ArticleContentTextBlock?
    let cells: [ArticleContentTableCell]
    let hasHeadingColumn: Bool

    init(heading: ArticleContentTextBlock?, cells: [ArticleContentTableCell], hasHeadingColumn: Bool? = nil) {
        self.heading = heading
        self.cells = cells
        self.hasHeadingColumn = hasHeadingColumn ?? (heading != nil)
    }

    var gridContents: [ArticleContentTextBlock?] {
        // A missing heading value still occupies a column. Its presence cannot
        // be inferred from cell count because HTML rows may have different lengths.
        hasHeadingColumn ? [heading] + cells.map(\.content) : cells.map(\.content)
    }

    static func == (lhs: ArticleContentTableRow, rhs: ArticleContentTableRow) -> Bool {
        lhs.heading == rhs.heading && lhs.cells == rhs.cells && lhs.hasHeadingColumn == rhs.hasHeadingColumn
    }
}

extension ArticleContentTableRow: Equatable {}

struct ArticleContentTableCell: Identifiable, Sendable {
    let id = UUID()
    let columnHeader: ArticleContentTextBlock?
    let content: ArticleContentTextBlock?

    static func == (lhs: ArticleContentTableCell, rhs: ArticleContentTableCell) -> Bool {
        lhs.columnHeader == rhs.columnHeader && lhs.content == rhs.content
    }
}

extension ArticleContentTableCell: Equatable {}

struct ArticleContentTextSpan: Equatable, Sendable {
    let text: String
    let linkURL: URL?
    let isStrong: Bool
    let isEmphasized: Bool
    let isCode: Bool
    let isMarked: Bool
    let verticalAlignment: ArticleContentInlineVerticalAlignment?
    let isDeleted: Bool
    let isInserted: Bool
    let codeSemantic: ArticleContentInlineCodeSemantic?
    let isCitation: Bool

    init(
        text: String,
        linkURL: URL? = nil,
        isStrong: Bool = false,
        isEmphasized: Bool = false,
        isCode: Bool = false,
        isMarked: Bool = false,
        verticalAlignment: ArticleContentInlineVerticalAlignment? = nil,
        isDeleted: Bool = false,
        isInserted: Bool = false,
        codeSemantic: ArticleContentInlineCodeSemantic? = nil,
        isCitation: Bool = false
    ) {
        self.text = text
        self.linkURL = linkURL
        self.isStrong = isStrong
        self.isEmphasized = isEmphasized
        self.isCode = isCode
        self.isMarked = isMarked
        self.verticalAlignment = verticalAlignment
        self.isDeleted = isDeleted
        self.isInserted = isInserted
        self.codeSemantic = codeSemantic
        self.isCitation = isCitation
    }
}

enum ArticleContentInlineVerticalAlignment: Equatable, Sendable {
    case superscript
    case lowered
}

enum ArticleContentInlineCodeSemantic: Equatable, Sendable {
    case keyboardInput
    case sampleOutput
    case variable
}

struct ArticleContentTextBlock: Equatable, Sendable {
    let spans: [ArticleContentTextSpan]

    var plainText: String {
        spans.map(\.text).joined()
    }

    init(spans: [ArticleContentTextSpan]) {
        self.spans = spans.filter { $0.text.isEmpty == false }
    }

    static func plainText(_ text: String) -> ArticleContentTextBlock {
        ArticleContentTextBlock(spans: [ArticleContentTextSpan(text: text)])
    }
}

enum ArticleContentNotice: Equatable, Sendable {
    case summaryOnly
    case emptyBody
}

enum ArticleContentBodySource: Equatable, Sendable {
    case summary
    case contentText
    case contentHTML
    case empty
}

struct ArticleContent: Equatable, Sendable {
    let blocks: [ArticleContentBodyBlock]
    let source: ArticleContentBodySource

    init(
        blocks: [ArticleContentBodyBlock],
        source: ArticleContentBodySource
    ) {
        self.blocks = blocks
        self.source = source
    }
}

extension ArticleContent {
    // Prefetch follows static figure/aside content. Disclosure children remain
    // excluded even when initially open, preserving the Reader prefetch policy.
    var firstImageURL: URL? {
        firstImageURL(in: blocks)
    }

    private func firstImageURL(in blocks: [ArticleContentBodyBlock]) -> URL? {
        for block in blocks {
            switch block {
            case .image(let url):
                return url
            case .figure(let figureBlocks), .aside(let figureBlocks):
                if let url = firstImageURL(in: figureBlocks) {
                    return url
                }
            default:
                continue
            }
        }
        return nil
    }
}
