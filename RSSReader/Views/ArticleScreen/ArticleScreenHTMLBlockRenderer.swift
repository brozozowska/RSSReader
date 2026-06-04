import Foundation

extension ArticleScreenBodyPayloadRenderer {
    static func renderHTML(
        _ contentHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
        let readableHTML = removingNonReadableHTMLBlocks(from: contentHTML)
        let htmlNSString = readableHTML as NSString
        let blockPattern = #"(?is)<(h[1-6]|p|blockquote|pre|ul|ol|figure|table|picture|iframe|video|audio)\b[^>]*>.*?</\1\s*>|<(img|hr|embed)\b[^>]*>"#
        guard let blockRegex = try? NSRegularExpression(pattern: blockPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return renderTextBlock(stripHTML(readableHTML))
        }

        var blocks: [ArticleScreenBodyBlock] = []
        var currentLocation = 0
        let matches = blockRegex.matches(
            in: readableHTML,
            options: [],
            range: NSRange(location: 0, length: htmlNSString.length)
        )

        for match in matches {
            let textRange = NSRange(location: currentLocation, length: match.range.location - currentLocation)
            if textRange.length > 0 {
                let textSegment = htmlNSString.substring(with: textRange)
                blocks.append(contentsOf: renderHTMLTextSegment(textSegment, article: article))
            }

            let blockHTML = htmlNSString.substring(with: match.range)
            blocks.append(contentsOf: renderHTMLBlock(blockHTML, article: article))

            currentLocation = match.range.location + match.range.length
        }

        if currentLocation < htmlNSString.length {
            let trailingRange = NSRange(location: currentLocation, length: htmlNSString.length - currentLocation)
            let trailingSegment = htmlNSString.substring(with: trailingRange)
            blocks.append(contentsOf: renderHTMLTextSegment(trailingSegment, article: article))
        }

        return blocks
    }

    static func renderHTMLBlock(
        _ blockHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
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
            let quotedBlocks = renderHTMLTextSegment(innerHTML, article: article).compactMap { block -> ArticleScreenTextBlock? in
                if case .paragraph(let textBlock) = block {
                    return textBlock
                }
                return nil
            }
            return quotedBlocks.isEmpty ? [] : [.blockquote(quotedBlocks)]
        case "pre":
            let codeText = stripHTML(innerHTML).trimmingCharacters(in: .whitespacesAndNewlines)
            return codeText.isEmpty ? [] : [.codeBlock(codeText)]
        case "ul":
            return renderHTMLList(innerHTML, kind: .unordered, article: article)
        case "ol":
            return renderHTMLList(innerHTML, kind: .ordered, article: article)
        case "figure":
            return renderHTMLFigure(innerHTML, article: article)
        case "table":
            return renderHTMLTableFallback(innerHTML, article: article)
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

    static func renderHTMLList(
        _ innerHTML: String,
        kind: ArticleScreenListKind,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
        let itemPattern = #"(?is)<li\b[^>]*>(.*?)</li\s*>"#
        guard let itemRegex = try? NSRegularExpression(pattern: itemPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return renderHTMLTextSegment(innerHTML, article: article)
        }

        let nsHTML = innerHTML as NSString
        let items = itemRegex.matches(
            in: innerHTML,
            options: [],
            range: NSRange(location: 0, length: nsHTML.length)
        )
        .compactMap { match -> ArticleScreenTextBlock? in
            let itemHTML = nsHTML.substring(with: match.range(at: 1))
            return makeTextBlock(fromHTML: itemHTML, article: article)
        }

        return items.isEmpty ? [] : [.list(ArticleScreenListBlock(kind: kind, items: items))]
    }

    static func renderHTMLTableFallback(
        _ innerHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
        let fallbackHTML = innerHTML
            .replacingOccurrences(
                of: #"(?i)</(th|td)\s*>"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)</tr\s*>"#,
                with: "\n",
                options: .regularExpression
            )

        return renderHTMLTextSegment(fallbackHTML, article: article)
    }

    static func renderHTMLFigure(
        _ innerHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
        var blocks: [ArticleScreenBodyBlock] = []

        if let imageBlocks = firstHTMLMediaImageBlocks(in: innerHTML, article: article) {
            blocks.append(contentsOf: imageBlocks)
        }

        if let captionHTML = firstHTMLBlock(named: "figcaption", in: innerHTML),
           let captionText = makeTextBlock(fromHTML: unwrapHTMLBlock(captionHTML), article: article) {
            blocks.append(.caption(captionText))
        }

        if blocks.isEmpty {
            return renderHTMLTextSegment(innerHTML, article: article)
        }

        return blocks
    }

    static func renderHTMLPicture(
        _ innerHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
        firstHTMLMediaImageBlocks(in: innerHTML, article: article) ?? []
    }

    static func firstHTMLMediaImageBlocks(
        in innerHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock]? {
        if let pictureURL = resolvePictureImageURL(fromInnerHTML: innerHTML, article: article) {
            return [.image(pictureURL)]
        }

        if let imageTag = firstHTMLTag(named: "img", in: innerHTML) {
            let imageBlocks = renderImageOrMediaFallback(fromImageTag: imageTag, article: article)
            if imageBlocks.isEmpty == false {
                return imageBlocks
            }
        }

        return nil
    }

    static func renderUnsupportedMediaFallback(
        tagName: String,
        html: String,
        innerHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
        guard let mediaURL = resolveMediaFallbackURL(fromHTML: html, article: article) else {
            return renderHTMLTextSegment(innerHTML, article: article)
        }

        let label = unsupportedMediaFallbackTitle(for: tagName)
        return mediaFallbackBlock(title: label, url: mediaURL)
    }

    static func renderImageOrMediaFallback(
        fromImageTag imageTag: String,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
        if let imageURL = resolveImageURL(fromImageTag: imageTag, article: article) {
            return [.image(imageURL)]
        }

        if let mediaFallback = resolveVideoLikeMediaFallback(fromHTML: imageTag, article: article) {
            return mediaFallbackBlock(title: mediaFallback.kind.title, url: mediaFallback.url)
        }

        return []
    }

    static func mediaFallbackBlock(
        title: String,
        url: URL
    ) -> [ArticleScreenBodyBlock] {
        return [
            .paragraph(
                ArticleScreenTextBlock(
                    spans: [
                        ArticleScreenTextSpan(text: title, linkURL: url)
                    ]
                )
            )
        ]
    }
}
