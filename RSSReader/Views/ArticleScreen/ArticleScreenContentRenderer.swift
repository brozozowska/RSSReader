import Foundation

@MainActor
enum ArticleScreenBodyBlock: Equatable {
    case paragraph(ArticleScreenTextBlock)
    case image(URL)
    case fallbackNotice(String)
}

struct ArticleScreenTextSpan: Equatable, Sendable {
    let text: String
    let linkURL: URL?

    init(text: String, linkURL: URL? = nil) {
        self.text = text
        self.linkURL = linkURL
    }
}

struct ArticleScreenTextBlock: Equatable, Sendable {
    let spans: [ArticleScreenTextSpan]

    var plainText: String {
        spans.map(\.text).joined()
    }

    init(spans: [ArticleScreenTextSpan]) {
        self.spans = spans.filter { $0.text.isEmpty == false }
    }

    static func plainText(_ text: String) -> ArticleScreenTextBlock {
        ArticleScreenTextBlock(spans: [ArticleScreenTextSpan(text: text)])
    }
}

@MainActor
enum ArticleScreenContentRenderer {
    static func renderBody(for article: ReaderArticleDTO) -> ArticleScreenBodyContentState {
        // TODO: When full-text extraction is implemented, resolve extracted content upstream
        // and construct ArticleScreenBodyContentState.extractedFullText(...) here without
        // teaching ReaderView a separate full-text rendering path.
        if let contentHTML = article.contentHTML?.nilIfBlank {
            let htmlBlocks = renderHTML(contentHTML, article: article)
            if htmlBlocks.isEmpty == false {
                return ArticleScreenBodyContentState(
                    blocks: appendLeadImageIfNeeded(htmlBlocks, article: article),
                    source: .contentHTML
                )
            }
        }

        if let contentText = article.contentText?.nilIfBlank {
            let textBlocks = renderTextBlock(contentText)
            if textBlocks.isEmpty == false {
                return ArticleScreenBodyContentState(
                    blocks: appendLeadImageIfNeeded(textBlocks, article: article),
                    source: .contentText
                )
            }
        }

        if let summary = article.summary?.nilIfBlank {
            var summaryBlocks = renderTextBlock(summary)
            summaryBlocks = appendLeadImageIfNeeded(summaryBlocks, article: article)
            summaryBlocks.append(
                ArticleScreenBodyBlock.fallbackNotice(
                    "This source only provides a summary, not the full article body."
                )
            )

            return ArticleScreenBodyContentState(
                blocks: summaryBlocks,
                source: .summary
            )
        }

        var fallbackBlocks: [ArticleScreenBodyBlock] = []
        if let imageBlock = leadImageBlock(for: article) {
            fallbackBlocks.append(imageBlock)
        }
        fallbackBlocks.append(
            ArticleScreenBodyBlock.fallbackNotice("Full article content is unavailable in this feed.")
        )

        return ArticleScreenBodyContentState(
            blocks: fallbackBlocks,
            source: .empty
        )
    }

    private static func renderHTML(
        _ contentHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
        let htmlNSString = contentHTML as NSString
        let imageTagPattern = #"<img\b[^>]*>"#
        guard let imageTagRegex = try? NSRegularExpression(pattern: imageTagPattern, options: [.caseInsensitive]) else {
            return renderTextBlock(stripHTML(contentHTML))
        }

        var blocks: [ArticleScreenBodyBlock] = []
        var currentLocation = 0
        let matches = imageTagRegex.matches(
            in: contentHTML,
            options: [],
            range: NSRange(location: 0, length: htmlNSString.length)
        )

        for match in matches {
            let textRange = NSRange(location: currentLocation, length: match.range.location - currentLocation)
            if textRange.length > 0 {
                let textSegment = htmlNSString.substring(with: textRange)
                blocks.append(contentsOf: renderHTMLTextSegment(textSegment, article: article))
            }

            let imageTag = htmlNSString.substring(with: match.range)
            if let imageURL = resolveImageURL(fromImageTag: imageTag, article: article) {
                blocks.append(.image(imageURL))
            }

            currentLocation = match.range.location + match.range.length
        }

        if currentLocation < htmlNSString.length {
            let trailingRange = NSRange(location: currentLocation, length: htmlNSString.length - currentLocation)
            let trailingSegment = htmlNSString.substring(with: trailingRange)
            blocks.append(contentsOf: renderHTMLTextSegment(trailingSegment, article: article))
        }

        return blocks
    }

    private static func renderTextBlock(_ text: String) -> [ArticleScreenBodyBlock] {
        splitIntoParagraphStrings(text).map { paragraph in
            .paragraph(makeTextBlock(fromPlainText: paragraph))
        }
    }

    private static func renderHTMLTextSegment(
        _ htmlSegment: String,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
        let normalizedHTML = htmlSegment
            .replacingOccurrences(
                of: #"(?i)<br\s*/?>"#,
                with: "\n",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)</?(p|div|section|article|blockquote|ul|ol|li|h[1-6]|pre)\b[^>]*>"#,
                with: "\n\n",
                options: .regularExpression
            )
        let htmlNSString = normalizedHTML as NSString
        let anchorPattern = #"<a\b[^>]*href\s*=\s*["']?([^"' >]+)["']?[^>]*>(.*?)</a>"#
        guard let anchorRegex = try? NSRegularExpression(
            pattern: anchorPattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return renderTextBlock(stripHTML(normalizedHTML))
        }

        var renderedBlocks: [ArticleScreenBodyBlock] = []
        var currentParagraphSpans: [ArticleScreenTextSpan] = []
        var currentLocation = 0
        let matches = anchorRegex.matches(
            in: normalizedHTML,
            options: [],
            range: NSRange(location: 0, length: htmlNSString.length)
        )

        for match in matches {
            let leadingRange = NSRange(location: currentLocation, length: match.range.location - currentLocation)
            if leadingRange.length > 0 {
                let leadingHTML = htmlNSString.substring(with: leadingRange)
                appendHTMLFragment(
                    leadingHTML,
                    article: article,
                    to: &renderedBlocks,
                    currentParagraphSpans: &currentParagraphSpans
                )
            }

            let rawHref = htmlNSString.substring(with: match.range(at: 1))
            let linkText = stripHTML(htmlNSString.substring(with: match.range(at: 2)))
            appendTextSegment(
                linkText,
                linkURL: ArticleScreenURLResolver.resolveArticleBodyLinkURL(
                    rawValue: rawHref,
                    baseURLString: article.canonicalURL ?? article.articleURL
                ),
                renderedBlocks: &renderedBlocks,
                currentParagraphSpans: &currentParagraphSpans
            )

            currentLocation = match.range.location + match.range.length
        }

        if currentLocation < htmlNSString.length {
            let trailingRange = NSRange(location: currentLocation, length: htmlNSString.length - currentLocation)
            let trailingHTML = htmlNSString.substring(with: trailingRange)
            appendHTMLFragment(
                trailingHTML,
                article: article,
                to: &renderedBlocks,
                currentParagraphSpans: &currentParagraphSpans
            )
        }

        finalizeParagraph(&currentParagraphSpans, into: &renderedBlocks)
        return renderedBlocks
    }

    private static func appendLeadImageIfNeeded(
        _ blocks: [ArticleScreenBodyBlock],
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
        guard blocks.containsImageBlock == false, let imageBlock = leadImageBlock(for: article) else {
            return blocks
        }

        return [imageBlock] + blocks
    }

    private static func leadImageBlock(for article: ReaderArticleDTO) -> ArticleScreenBodyBlock? {
        guard
            let imageURLString = article.imageURL?.nilIfBlank,
            let imageURL = ArticleScreenURLResolver.resolveMediaURL(
                rawValue: imageURLString,
                baseURLString: article.canonicalURL ?? article.articleURL
            )
        else {
            return nil
        }

        return .image(imageURL)
    }

    private static func resolveImageURL(
        fromImageTag imageTag: String,
        article: ReaderArticleDTO
    ) -> URL? {
        let srcPattern = #"src\s*=\s*["']?([^"' >]+)"?"#
        guard
            let srcRegex = try? NSRegularExpression(pattern: srcPattern, options: [.caseInsensitive]),
            let match = srcRegex.firstMatch(
                in: imageTag,
                options: [],
                range: NSRange(location: 0, length: (imageTag as NSString).length)
            ),
            match.numberOfRanges > 1
        else {
            return nil
        }

        let rawImageURL = (imageTag as NSString).substring(with: match.range(at: 1))
        return ArticleScreenURLResolver.resolveMediaURL(
            rawValue: rawImageURL,
            baseURLString: article.canonicalURL ?? article.articleURL
        )
    }

    private static func stripHTML(_ value: String) -> String {
        value
            .replacingOccurrences(
                of: #"(?i)<br\s*/?>"#,
                with: "\n",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"(?i)</?(p|div|section|article|blockquote|ul|ol|li|h[1-6]|pre)\b[^>]*>"#,
                with: "\n\n",
                options: .regularExpression
            )
            .replacingOccurrences(
                of: #"<[^>]+>"#,
                with: "",
                options: .regularExpression
            )
            .decodingBasicHTMLEntities()
    }

    private static func appendHTMLFragment(
        _ htmlFragment: String,
        article: ReaderArticleDTO,
        to renderedBlocks: inout [ArticleScreenBodyBlock],
        currentParagraphSpans: inout [ArticleScreenTextSpan]
    ) {
        _ = article
        appendTextSegment(
            stripHTML(htmlFragment),
            linkURL: nil,
            renderedBlocks: &renderedBlocks,
            currentParagraphSpans: &currentParagraphSpans
        )
    }

    private static func appendTextSegment(
        _ text: String,
        linkURL: URL?,
        renderedBlocks: inout [ArticleScreenBodyBlock],
        currentParagraphSpans: inout [ArticleScreenTextSpan]
    ) {
        let normalizedText = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        guard normalizedText.isEmpty == false else { return }

        let separatorPattern = #"\n\s*\n+"#
        guard let separatorRegex = try? NSRegularExpression(pattern: separatorPattern) else {
            appendInlineText(
                normalizedText.replacingOccurrences(of: #"\s*\n\s*"#, with: " ", options: .regularExpression),
                linkURL: linkURL,
                to: &currentParagraphSpans
            )
            return
        }

        let normalizedNSString = normalizedText as NSString
        let separatorMatches = separatorRegex.matches(
            in: normalizedText,
            options: [],
            range: NSRange(location: 0, length: normalizedNSString.length)
        )

        var currentLocation = 0
        for separator in separatorMatches {
            let chunkRange = NSRange(location: currentLocation, length: separator.range.location - currentLocation)
            if chunkRange.length > 0 {
                let chunk = normalizedNSString.substring(with: chunkRange)
                appendInlineText(
                    chunk.replacingOccurrences(of: #"\s*\n\s*"#, with: " ", options: .regularExpression),
                    linkURL: linkURL,
                    to: &currentParagraphSpans
                )
            }

            finalizeParagraph(&currentParagraphSpans, into: &renderedBlocks)
            currentLocation = separator.range.location + separator.range.length
        }

        if currentLocation < normalizedNSString.length {
            let trailingRange = NSRange(location: currentLocation, length: normalizedNSString.length - currentLocation)
            let trailingChunk = normalizedNSString.substring(with: trailingRange)
            appendInlineText(
                trailingChunk.replacingOccurrences(of: #"\s*\n\s*"#, with: " ", options: .regularExpression),
                linkURL: linkURL,
                to: &currentParagraphSpans
            )
        }
    }

    private static func appendInlineText(
        _ text: String,
        linkURL: URL?,
        to spans: inout [ArticleScreenTextSpan]
    ) {
        guard text.isEmpty == false else { return }

        if let lastSpan = spans.last, lastSpan.linkURL == linkURL {
            spans[spans.count - 1] = ArticleScreenTextSpan(
                text: lastSpan.text + text,
                linkURL: linkURL
            )
        } else {
            spans.append(ArticleScreenTextSpan(text: text, linkURL: linkURL))
        }
    }

    private static func finalizeParagraph(
        _ spans: inout [ArticleScreenTextSpan],
        into renderedBlocks: inout [ArticleScreenBodyBlock]
    ) {
        let trimmedSpans = trimBoundaryWhitespace(in: spans)
        guard trimmedSpans.isEmpty == false else {
            spans = []
            return
        }

        renderedBlocks.append(.paragraph(ArticleScreenTextBlock(spans: trimmedSpans)))
        spans = []
    }

    private static func makeTextBlock(fromPlainText text: String) -> ArticleScreenTextBlock {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let nsText = text as NSString
        let matches = detector?.matches(
            in: text,
            options: [],
            range: NSRange(location: 0, length: nsText.length)
        ) ?? []

        var spans: [ArticleScreenTextSpan] = []
        var currentLocation = 0

        for match in matches {
            let leadingRange = NSRange(location: currentLocation, length: match.range.location - currentLocation)
            if leadingRange.length > 0 {
                spans.append(ArticleScreenTextSpan(text: nsText.substring(with: leadingRange)))
            }

            let linkText = nsText.substring(with: match.range)
            let linkURL = match.url.flatMap { url in
                ArticleScreenURLResolver.resolveArticleBodyLinkURL(
                    rawValue: url.absoluteString,
                    baseURLString: nil
                )
            }
            spans.append(ArticleScreenTextSpan(text: linkText, linkURL: linkURL))
            currentLocation = match.range.location + match.range.length
        }

        if currentLocation < nsText.length {
            let trailingRange = NSRange(location: currentLocation, length: nsText.length - currentLocation)
            spans.append(ArticleScreenTextSpan(text: nsText.substring(with: trailingRange)))
        }

        return ArticleScreenTextBlock(spans: mergedSpans(spans))
    }

    private static func splitIntoParagraphStrings(_ text: String) -> [String] {
        text
            .normalizedParagraphs
            .filter { $0.isEmpty == false }
    }

    private static func trimBoundaryWhitespace(in spans: [ArticleScreenTextSpan]) -> [ArticleScreenTextSpan] {
        var trimmedSpans = spans

        while let firstSpan = trimmedSpans.first {
            let trimmedText = firstSpan.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText.isEmpty {
                trimmedSpans.removeFirst()
            } else {
                trimmedSpans[0] = ArticleScreenTextSpan(text: trimLeadingWhitespace(in: firstSpan.text), linkURL: firstSpan.linkURL)
                break
            }
        }

        while let lastSpan = trimmedSpans.last {
            let trimmedText = lastSpan.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText.isEmpty {
                trimmedSpans.removeLast()
            } else {
                trimmedSpans[trimmedSpans.count - 1] = ArticleScreenTextSpan(
                    text: trimTrailingWhitespace(in: lastSpan.text),
                    linkURL: lastSpan.linkURL
                )
                break
            }
        }

        return mergedSpans(trimmedSpans.filter { $0.text.isEmpty == false })
    }

    private static func mergedSpans(_ spans: [ArticleScreenTextSpan]) -> [ArticleScreenTextSpan] {
        spans.reduce(into: [ArticleScreenTextSpan]()) { partialResult, span in
            guard span.text.isEmpty == false else { return }

            if let lastSpan = partialResult.last, lastSpan.linkURL == span.linkURL {
                partialResult[partialResult.count - 1] = ArticleScreenTextSpan(
                    text: lastSpan.text + span.text,
                    linkURL: span.linkURL
                )
            } else {
                partialResult.append(span)
            }
        }
    }

    private static func trimLeadingWhitespace(in value: String) -> String {
        String(value.drop(while: { $0.isWhitespace }))
    }

    private static func trimTrailingWhitespace(in value: String) -> String {
        String(value.reversed().drop(while: { $0.isWhitespace }).reversed())
    }
}

private extension Array where Element == ArticleScreenBodyBlock {
    var containsImageBlock: Bool {
        contains {
            if case .image = $0 {
                return true
            }
            return false
        }
    }
}

private extension String {
    var nilIfBlank: String? {
        let trimmedValue = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    var normalizedParagraphs: [String] {
        replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n\n")
            .map { paragraph in
                paragraph
                    .components(separatedBy: .newlines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { $0.isEmpty == false }
                    .joined(separator: " ")
            }
            .filter { $0.isEmpty == false }
    }

    func decodingBasicHTMLEntities() -> String {
        self
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
    }
}
