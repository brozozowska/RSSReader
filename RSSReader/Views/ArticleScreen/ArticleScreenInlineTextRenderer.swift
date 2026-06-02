import Foundation

struct ArticleScreenInlineTextStyle {
    var linkURL: URL?
    var isStrong = false
    var isEmphasized = false
    var isCode = false
}

extension ArticleScreenBodyPayloadRenderer {
    static func renderTextBlock(_ text: String) -> [ArticleScreenBodyBlock] {
        splitIntoParagraphStrings(text).map { paragraph in
            .paragraph(makeTextBlock(fromPlainText: paragraph))
        }
    }

    static func renderHTMLTextSegment(
        _ htmlSegment: String,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
        let normalizedHTML = removingNonReadableHTMLBlocks(from: htmlSegment)
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

    static func makeTextBlock(
        fromHTML html: String,
        article: ReaderArticleDTO
    ) -> ArticleScreenTextBlock? {
        var spans: [ArticleScreenTextSpan] = []
        appendInlineHTML(
            html,
            article: article,
            style: ArticleScreenInlineTextStyle(),
            to: &spans
        )

        let trimmedSpans = trimBoundaryWhitespace(in: spans)
        return trimmedSpans.isEmpty ? nil : ArticleScreenTextBlock(spans: trimmedSpans)
    }

    static func appendInlineHTML(
        _ html: String,
        article: ReaderArticleDTO,
        style: ArticleScreenInlineTextStyle,
        to spans: inout [ArticleScreenTextSpan]
    ) {
        let inlinePattern = #"(?is)<br\s*/?>|<(a|strong|b|em|i|code)\b([^>]*)>(.*?)</\1\s*>"#
        guard let inlineRegex = try? NSRegularExpression(
            pattern: inlinePattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            appendStyledHTMLFragment(html, style: style, to: &spans)
            return
        }

        let nsHTML = html as NSString
        let matches = inlineRegex.matches(
            in: html,
            options: [],
            range: NSRange(location: 0, length: nsHTML.length)
        )

        var currentLocation = 0
        for match in matches {
            let leadingRange = NSRange(location: currentLocation, length: match.range.location - currentLocation)
            if leadingRange.length > 0 {
                appendStyledHTMLFragment(
                    nsHTML.substring(with: leadingRange),
                    style: style,
                    to: &spans
                )
            }

            if match.range(at: 1).location == NSNotFound {
                appendStyledText(" ", style: style, to: &spans)
            } else {
                let tagName = nsHTML.substring(with: match.range(at: 1)).lowercased()
                let attributes = nsHTML.substring(with: match.range(at: 2))
                let innerHTML = nsHTML.substring(with: match.range(at: 3))
                var childStyle = style

                switch tagName {
                case "a":
                    if let rawHref = htmlAttribute(named: "href", in: attributes) {
                        childStyle.linkURL = ArticleScreenURLResolver.resolveArticleBodyLinkURL(
                            rawValue: rawHref,
                            baseURLString: article.canonicalURL ?? article.articleURL
                        )
                    }
                case "strong", "b":
                    childStyle.isStrong = true
                case "em", "i":
                    childStyle.isEmphasized = true
                case "code":
                    childStyle.isCode = true
                default:
                    break
                }

                appendInlineHTML(innerHTML, article: article, style: childStyle, to: &spans)
            }

            currentLocation = match.range.location + match.range.length
        }

        if currentLocation < nsHTML.length {
            let trailingRange = NSRange(location: currentLocation, length: nsHTML.length - currentLocation)
            appendStyledHTMLFragment(
                nsHTML.substring(with: trailingRange),
                style: style,
                to: &spans
            )
        }
    }

    static func appendStyledHTMLFragment(
        _ htmlFragment: String,
        style: ArticleScreenInlineTextStyle,
        to spans: inout [ArticleScreenTextSpan]
    ) {
        let strippedText = stripHTML(htmlFragment)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        appendStyledText(strippedText, style: style, to: &spans)
    }

    static func appendStyledText(
        _ text: String,
        style: ArticleScreenInlineTextStyle,
        to spans: inout [ArticleScreenTextSpan]
    ) {
        appendInlineText(
            text,
            linkURL: style.linkURL,
            isStrong: style.isStrong,
            isEmphasized: style.isEmphasized,
            isCode: style.isCode,
            to: &spans
        )
    }

    static func appendHTMLFragment(
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

    static func appendTextSegment(
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
                isStrong: false,
                isEmphasized: false,
                isCode: false,
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
                    isStrong: false,
                    isEmphasized: false,
                    isCode: false,
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
                isStrong: false,
                isEmphasized: false,
                isCode: false,
                to: &currentParagraphSpans
            )
        }
    }

    static func appendInlineText(
        _ text: String,
        linkURL: URL?,
        isStrong: Bool,
        isEmphasized: Bool,
        isCode: Bool,
        to spans: inout [ArticleScreenTextSpan]
    ) {
        guard text.isEmpty == false else { return }

        if let lastSpan = spans.last,
           lastSpan.linkURL == linkURL,
           lastSpan.isStrong == isStrong,
           lastSpan.isEmphasized == isEmphasized,
           lastSpan.isCode == isCode {
            spans[spans.count - 1] = ArticleScreenTextSpan(
                text: lastSpan.text + text,
                linkURL: linkURL,
                isStrong: isStrong,
                isEmphasized: isEmphasized,
                isCode: isCode
            )
        } else {
            spans.append(
                ArticleScreenTextSpan(
                    text: text,
                    linkURL: linkURL,
                    isStrong: isStrong,
                    isEmphasized: isEmphasized,
                    isCode: isCode
                )
            )
        }
    }

    static func finalizeParagraph(
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

    static func makeTextBlock(fromPlainText text: String) -> ArticleScreenTextBlock {
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

    static func splitIntoParagraphStrings(_ text: String) -> [String] {
        text
            .articleScreenNormalizedParagraphs
            .filter { $0.isEmpty == false }
    }

    static func trimBoundaryWhitespace(in spans: [ArticleScreenTextSpan]) -> [ArticleScreenTextSpan] {
        var trimmedSpans = spans

        while let firstSpan = trimmedSpans.first {
            let trimmedText = firstSpan.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmedText.isEmpty {
                trimmedSpans.removeFirst()
            } else {
                trimmedSpans[0] = ArticleScreenTextSpan(
                    text: trimLeadingWhitespace(in: firstSpan.text),
                    linkURL: firstSpan.linkURL,
                    isStrong: firstSpan.isStrong,
                    isEmphasized: firstSpan.isEmphasized,
                    isCode: firstSpan.isCode
                )
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
                    linkURL: lastSpan.linkURL,
                    isStrong: lastSpan.isStrong,
                    isEmphasized: lastSpan.isEmphasized,
                    isCode: lastSpan.isCode
                )
                break
            }
        }

        return mergedSpans(trimmedSpans.filter { $0.text.isEmpty == false })
    }

    static func mergedSpans(_ spans: [ArticleScreenTextSpan]) -> [ArticleScreenTextSpan] {
        spans.reduce(into: [ArticleScreenTextSpan]()) { partialResult, span in
            guard span.text.isEmpty == false else { return }

            if let lastSpan = partialResult.last,
               lastSpan.linkURL == span.linkURL,
               lastSpan.isStrong == span.isStrong,
               lastSpan.isEmphasized == span.isEmphasized,
               lastSpan.isCode == span.isCode {
                partialResult[partialResult.count - 1] = ArticleScreenTextSpan(
                    text: lastSpan.text + span.text,
                    linkURL: span.linkURL,
                    isStrong: span.isStrong,
                    isEmphasized: span.isEmphasized,
                    isCode: span.isCode
                )
            } else {
                partialResult.append(span)
            }
        }
    }

    static func trimLeadingWhitespace(in value: String) -> String {
        String(value.drop(while: { $0.isWhitespace }))
    }

    static func trimTrailingWhitespace(in value: String) -> String {
        String(value.reversed().drop(while: { $0.isWhitespace }).reversed())
    }
}
