import Foundation

extension ArticleContentBodyPayloadRenderer {
    static func renderHTMLBlock(
        _ blockHTML: String,
        article: ReaderArticleDTO,
        containerDepth: Int
    ) -> [ArticleContentBodyBlock] {
        let tagName = leadingTagName(in: blockHTML)

        if tagName == "img" {
            return renderImageOrMediaFallback(fromImageTag: blockHTML, article: article)
        }

        if tagName == "hr" {
            return [.divider]
        }

        let innerHTML = unwrapHTMLBlock(blockHTML)

        switch tagName {
        case "h1", "h2", "h3", "h4", "h5", "h6":
            guard let headingText = makeTextBlock(fromHTML: innerHTML, article: article) else { return [] }
            let level = Int(String(tagName.dropFirst())) ?? 2
            return [.heading(level: level, headingText)]
        case "p":
            return makeTextBlock(fromHTML: innerHTML, article: article).map { [.paragraph($0)] } ?? []
        case "blockquote":
            let quotedBlocks = renderHTMLTextSegment(innerHTML, article: article).compactMap { block -> ArticleContentTextBlock? in
                if case .paragraph(let textBlock) = block {
                    return textBlock
                }
                return nil
            }
            return quotedBlocks.isEmpty ? [] : [.blockquote(quotedBlocks)]
        case "pre":
            let trimmedInnerHTML = innerHTML.trimmingCharacters(in: .whitespacesAndNewlines)
            let isCode = trimmedInnerHTML.range(of: #"(?i)^<\s*code\b"#, options: .regularExpression) != nil
            let literalHTML = isCode ? unwrapHTMLBlock(trimmedInnerHTML) : innerHTML
            let literalText = ArticleContentBodyPayloadNormalizer.decodeHTMLEntities(in: literalHTML)
            guard literalText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return [] }
            // Preserve source whitespace, including the indentation of the first line.
            return [isCode ? .codeBlock(literalText) : .preformattedText(literalText)]
        case "ul":
            return renderHTMLList(innerHTML, kind: .unordered, article: article)
        case "ol":
            return renderHTMLList(innerHTML, kind: .ordered, article: article)
        case "dl":
            return renderHTMLDefinitionList(innerHTML, article: article)
        case "address":
            return makeTextBlock(fromHTML: innerHTML, article: article).map { [.address($0)] } ?? []
        case "figure":
            return renderHTMLFigure(innerHTML, article: article, containerDepth: containerDepth)
        case "figcaption":
            return makeTextBlock(fromHTML: innerHTML, article: article).map { [.caption($0)] } ?? []
        case "table":
            return renderHTMLTable(innerHTML, article: article)
        case "picture":
            return renderHTMLPicture(innerHTML, article: article)
        case "iframe", "video", "audio":
            return renderUnsupportedMediaFallback(
                tagName: tagName,
                html: blockHTML,
                innerHTML: innerHTML,
                article: article
            )
        case "embed":
            return renderUnsupportedMediaFallback(
                tagName: tagName,
                html: blockHTML,
                innerHTML: "",
                article: article
            )
        default:
            return renderHTMLTextSegment(blockHTML, article: article)
        }
    }
}
