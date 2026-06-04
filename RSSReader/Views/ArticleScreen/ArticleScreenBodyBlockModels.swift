import Foundation
@MainActor
enum ArticleScreenBodyBlock: Equatable {
    case heading(level: Int, ArticleScreenTextBlock)
    case paragraph(ArticleScreenTextBlock)
    case list(ArticleScreenListBlock)
    case blockquote([ArticleScreenTextBlock])
    case codeBlock(String)
    case divider
    case caption(ArticleScreenTextBlock)
    case image(URL)
    case fallbackNotice(String)
}

enum ArticleScreenListKind: Equatable, Sendable {
    case ordered
    case unordered
}

struct ArticleScreenListBlock: Equatable, Sendable {
    let kind: ArticleScreenListKind
    let items: [ArticleScreenTextBlock]
}

struct ArticleScreenTextSpan: Equatable, Sendable {
    let text: String
    let linkURL: URL?
    let isStrong: Bool
    let isEmphasized: Bool
    let isCode: Bool

    init(
        text: String,
        linkURL: URL? = nil,
        isStrong: Bool = false,
        isEmphasized: Bool = false,
        isCode: Bool = false
    ) {
        self.text = text
        self.linkURL = linkURL
        self.isStrong = isStrong
        self.isEmphasized = isEmphasized
        self.isCode = isCode
    }
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

        return intent.isEmpty ? nil : intent
    }
}
