import Foundation
import SwiftUI
@MainActor
enum ArticleScreenBodyBlock: Equatable {
    case heading(level: Int, ArticleScreenTextBlock)
    case paragraph(ArticleScreenTextBlock)
    case list(ArticleScreenListBlock)
    case definitionList(ArticleScreenDefinitionListBlock)
    case table(ArticleScreenTableBlock)
    indirect case disclosure(ArticleScreenDisclosureBlock)
    indirect case aside([ArticleScreenBodyBlock])
    indirect case figure([ArticleScreenBodyBlock])
    case address(ArticleScreenTextBlock)
    case blockquote([ArticleScreenTextBlock])
    case codeBlock(String)
    case divider
    case caption(ArticleScreenTextBlock)
    case image(URL)
    case media(ArticleScreenMediaBlock)
    case fallbackNotice(String)
}

struct ArticleScreenMediaBlock: Equatable, Sendable {
    let kind: ArticleScreenMediaKind
    let url: URL
}

enum ArticleScreenMediaKind: Equatable, Sendable {
    case audio
    case video
    case knownEmbedded
    case embedded
    case generic

    var actionTitle: String {
        switch self {
        case .audio:
            ReadingLocalization.openAudioAction
        case .video:
            ReadingLocalization.openVideoAction
        case .knownEmbedded, .embedded:
            ReadingLocalization.openEmbeddedContentAction
        case .generic:
            ReadingLocalization.openMediaAction
        }
    }
}

enum ArticleScreenListKind: Equatable, Sendable {
    case ordered
    case unordered
}

struct ArticleScreenListBlock: Equatable, Sendable {
    let kind: ArticleScreenListKind
    let items: [ArticleScreenTextBlock]
}

struct ArticleScreenDefinitionListBlock: Equatable, Sendable {
    let entries: [ArticleScreenDefinitionEntry]
}

struct ArticleScreenDefinitionEntry: Identifiable, Sendable {
    let id = UUID()
    let term: ArticleScreenTextBlock?
    let definitions: [ArticleScreenTextBlock?]

    static func == (lhs: ArticleScreenDefinitionEntry, rhs: ArticleScreenDefinitionEntry) -> Bool {
        lhs.term == rhs.term && lhs.definitions == rhs.definitions
    }
}

extension ArticleScreenDefinitionEntry: Equatable {}

struct ArticleScreenDisclosureBlock: Equatable {
    let summary: ArticleScreenTextBlock
    let content: [ArticleScreenBodyBlock]
    let isInitiallyExpanded: Bool
}

struct ArticleScreenTableBlock: Equatable, Sendable {
    let columnHeaders: [ArticleScreenTextBlock?]
    let headerSource: ArticleScreenTableHeaderSource?
    let rows: [ArticleScreenTableRow]
}

enum ArticleScreenTableHeaderSource: Equatable, Sendable {
    case explicit
    case inferred
}

struct ArticleScreenTableRow: Identifiable, Sendable {
    let id = UUID()
    let heading: ArticleScreenTextBlock?
    let cells: [ArticleScreenTableCell]
    let hasHeadingColumn: Bool

    init(heading: ArticleScreenTextBlock?, cells: [ArticleScreenTableCell], hasHeadingColumn: Bool? = nil) {
        self.heading = heading
        self.cells = cells
        self.hasHeadingColumn = hasHeadingColumn ?? (heading != nil)
    }

    var gridContents: [ArticleScreenTextBlock?] {
        // A missing heading value still occupies a column. Its presence cannot
        // be inferred from cell count because HTML rows may have different lengths.
        hasHeadingColumn ? [heading] + cells.map(\.content) : cells.map(\.content)
    }

    static func == (lhs: ArticleScreenTableRow, rhs: ArticleScreenTableRow) -> Bool {
        lhs.heading == rhs.heading && lhs.cells == rhs.cells && lhs.hasHeadingColumn == rhs.hasHeadingColumn
    }
}

extension ArticleScreenTableRow: Equatable {}

struct ArticleScreenTableCell: Identifiable, Sendable {
    let id = UUID()
    let columnHeader: ArticleScreenTextBlock?
    let content: ArticleScreenTextBlock?

    static func == (lhs: ArticleScreenTableCell, rhs: ArticleScreenTableCell) -> Bool {
        lhs.columnHeader == rhs.columnHeader && lhs.content == rhs.content
    }
}

extension ArticleScreenTableCell: Equatable {}

struct ArticleScreenTextSpan: Equatable, Sendable {
    let text: String
    let linkURL: URL?
    let isStrong: Bool
    let isEmphasized: Bool
    let isCode: Bool
    let isMarked: Bool
    let verticalAlignment: ArticleScreenInlineVerticalAlignment?
    let isDeleted: Bool
    let isInserted: Bool
    let codeSemantic: ArticleScreenInlineCodeSemantic?
    let isCitation: Bool

    init(
        text: String,
        linkURL: URL? = nil,
        isStrong: Bool = false,
        isEmphasized: Bool = false,
        isCode: Bool = false,
        isMarked: Bool = false,
        verticalAlignment: ArticleScreenInlineVerticalAlignment? = nil,
        isDeleted: Bool = false,
        isInserted: Bool = false,
        codeSemantic: ArticleScreenInlineCodeSemantic? = nil,
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

enum ArticleScreenInlineVerticalAlignment: Equatable, Sendable {
    case superscript
    case lowered
}

enum ArticleScreenInlineCodeSemantic: Equatable, Sendable {
    case keyboardInput
    case sampleOutput
    case variable
}

struct ArticleScreenTextBlock: Equatable, Sendable {
    let spans: [ArticleScreenTextSpan]

    var plainText: String {
        spans.map(\.text).joined()
    }

    var attributedString: AttributedString {
        spans.reduce(into: AttributedString()) { partialResult, span in
            var attributedSpan = AttributedString(span.text)
            attributedSpan.link = span.linkURL
            attributedSpan.inlinePresentationIntent = span.inlinePresentationIntent
            // Source <mark> semantics do not override the Reader theme's text styling.
            if span.isInserted {
                attributedSpan.underlineStyle = .single
            }
            if let verticalAlignment = span.verticalAlignment {
                attributedSpan.font = .caption
                attributedSpan.baselineOffset = verticalAlignment == .superscript ? 4 : -2
            }
            partialResult.append(attributedSpan)
        }
    }

    init(spans: [ArticleScreenTextSpan]) {
        self.spans = spans.filter { $0.text.isEmpty == false }
    }

    static func plainText(_ text: String) -> ArticleScreenTextBlock {
        ArticleScreenTextBlock(spans: [ArticleScreenTextSpan(text: text)])
    }
}

private extension ArticleScreenTextSpan {
    var inlinePresentationIntent: InlinePresentationIntent? {
        var intent = InlinePresentationIntent()

        if isStrong {
            intent.insert(.stronglyEmphasized)
        }
        if isEmphasized {
            intent.insert(.emphasized)
        }
        if isCode {
            intent.insert(.code)
        }
        if isDeleted {
            intent.insert(.strikethrough)
        }
        if isCitation || codeSemantic == .variable {
            intent.insert(.emphasized)
        }

        return intent.isEmpty ? nil : intent
    }
}
