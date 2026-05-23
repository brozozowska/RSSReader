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

private struct ArticleScreenInlineTextStyle {
    var linkURL: URL?
    var isStrong = false
    var isEmphasized = false
    var isCode = false
}

@MainActor
enum ArticleScreenContentRenderer {
    static func renderBody(for article: ReaderArticleDTO) -> ArticleScreenBodyContentState {
        if let contentHTML = ArticleScreenBodyPayloadNormalizer.normalize(
            article.contentHTML,
            preferredKind: .html
        ) {
            let bodyBlocks = renderBodyPayload(contentHTML, article: article)
            if bodyBlocks.isEmpty == false {
                return ArticleScreenBodyContentState(
                    blocks: appendLeadImageIfNeeded(bodyBlocks, article: article),
                    source: .contentHTML
                )
            }
        }

        if let contentText = ArticleScreenBodyPayloadNormalizer.normalize(
            article.contentText,
            preferredKind: .plainText
        ) {
            let bodyBlocks = renderBodyPayload(contentText, article: article)
            if bodyBlocks.isEmpty == false {
                return ArticleScreenBodyContentState(
                    blocks: appendLeadImageIfNeeded(bodyBlocks, article: article),
                    source: .contentText
                )
            }
        }

        if let summary = ArticleScreenBodyPayloadNormalizer.normalize(
            article.summary,
            preferredKind: .plainText
        ) {
            var summaryBlocks = renderBodyPayload(summary, article: article)
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

    private static func renderBodyPayload(
        _ payload: ArticleScreenBodyPayload,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
        switch payload.kind {
        case .plainText:
            renderTextBlock(payload.value)
        case .html:
            renderHTML(payload.value, article: article)
        }
    }

    private static func renderHTML(
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

    private static func renderHTMLBlock(
        _ blockHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
        let tagName = leadingTagName(in: blockHTML)

        if tagName == "img" {
            return resolveImageURL(fromImageTag: blockHTML, article: article).map { [.image($0)] } ?? []
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

    private static func renderHTMLList(
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

    private static func renderHTMLTableFallback(
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

    private static func renderHTMLFigure(
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

    private static func renderHTMLPicture(
        _ innerHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
        firstHTMLMediaImageBlocks(in: innerHTML, article: article) ?? []
    }

    private static func firstHTMLMediaImageBlocks(
        in innerHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock]? {
        if let pictureURL = resolvePictureImageURL(fromInnerHTML: innerHTML, article: article) {
            return [.image(pictureURL)]
        }

        if let imageTag = firstHTMLTag(named: "img", in: innerHTML),
           let imageURL = resolveImageURL(fromImageTag: imageTag, article: article) {
            return [.image(imageURL)]
        }

        return nil
    }

    private static func renderUnsupportedMediaFallback(
        tagName: String,
        html: String,
        innerHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleScreenBodyBlock] {
        guard let mediaURL = resolveMediaFallbackURL(fromHTML: html, article: article) else {
            return renderHTMLTextSegment(innerHTML, article: article)
        }

        let label = unsupportedMediaFallbackTitle(for: tagName)
        return [
            .paragraph(
                ArticleScreenTextBlock(
                    spans: [
                        ArticleScreenTextSpan(text: label, linkURL: mediaURL)
                    ]
                )
            )
        ]
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

    private static func makeTextBlock(
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

    private static func appendInlineHTML(
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

    private static func appendStyledHTMLFragment(
        _ htmlFragment: String,
        style: ArticleScreenInlineTextStyle,
        to spans: inout [ArticleScreenTextSpan]
    ) {
        let strippedText = stripHTML(htmlFragment)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        appendStyledText(strippedText, style: style, to: &spans)
    }

    private static func appendStyledText(
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
        let directAttributes = [
            "data-src",
            "data-original",
            "data-lazy-src",
            "data-url",
            "src"
        ]

        for attributeName in directAttributes {
            if let rawURL = htmlAttribute(named: attributeName, in: imageTag),
               let imageURL = resolveArticleMediaURL(rawURL, article: article) {
                return imageURL
            }
        }

        let srcsetAttributes = [
            "data-srcset",
            "srcset"
        ]

        for attributeName in srcsetAttributes {
            if let rawSrcset = htmlAttribute(named: attributeName, in: imageTag),
               let rawURL = preferredURLCandidate(fromSrcset: rawSrcset),
               let imageURL = resolveArticleMediaURL(rawURL, article: article) {
                return imageURL
            }
        }

        return nil
    }

    private static func resolvePictureImageURL(
        fromInnerHTML innerHTML: String,
        article: ReaderArticleDTO
    ) -> URL? {
        if let imageTag = firstHTMLTag(named: "img", in: innerHTML),
           let imageURL = resolveImageURL(fromImageTag: imageTag, article: article) {
            return imageURL
        }

        for sourceTag in htmlTags(named: "source", in: innerHTML) {
            if let rawSrcset = htmlAttribute(named: "srcset", in: sourceTag),
               let rawURL = preferredURLCandidate(fromSrcset: rawSrcset),
               let imageURL = resolveArticleMediaURL(rawURL, article: article) {
                return imageURL
            }
        }

        return nil
    }

    private static func resolveMediaFallbackURL(
        fromHTML html: String,
        article: ReaderArticleDTO
    ) -> URL? {
        let directAttributes = [
            "src",
            "data-src",
            "data-original",
            "data-url",
            "href"
        ]

        for attributeName in directAttributes {
            if let rawURL = htmlAttribute(named: attributeName, in: html),
               let mediaURL = resolveArticleMediaURL(rawURL, article: article) {
                return mediaURL
            }
        }

        return nil
    }

    private static func resolveArticleMediaURL(
        _ rawValue: String,
        article: ReaderArticleDTO
    ) -> URL? {
        let trimmedValue = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedValue.isEmpty == false, trimmedValue.lowercased().hasPrefix("data:") == false else {
            return nil
        }
        guard trimmedValue.lowercased().hasSuffix(".svg") == false else {
            return nil
        }

        return ArticleScreenURLResolver.resolveMediaURL(
            rawValue: trimmedValue,
            baseURLString: article.articleURL
        )
    }

    private static func preferredURLCandidate(fromSrcset srcset: String) -> String? {
        srcset
            .split(separator: ",")
            .compactMap { candidate -> String? in
                candidate
                    .split(whereSeparator: { $0.isWhitespace })
                    .first
                    .map(String.init)
            }
            .last?
            .nilIfBlank
    }

    private static func unsupportedMediaFallbackTitle(for tagName: String) -> String {
        switch tagName {
        case "iframe":
            "Open embedded content"
        case "video":
            "Open video"
        case "audio":
            "Open audio"
        default:
            "Open media"
        }
    }

    private static func leadingTagName(in html: String) -> String {
        guard
            let tagRegex = try? NSRegularExpression(pattern: #"<\s*([a-zA-Z0-9]+)"#, options: []),
            let match = tagRegex.firstMatch(
                in: html,
                options: [],
                range: NSRange(location: 0, length: (html as NSString).length)
            ),
            match.numberOfRanges > 1
        else {
            return ""
        }

        return (html as NSString).substring(with: match.range(at: 1)).lowercased()
    }

    private static func unwrapHTMLBlock(_ html: String) -> String {
        html
            .replacingOccurrences(of: #"(?is)^<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)</[^>]+>\s*$"#, with: "", options: .regularExpression)
    }

    private static func firstHTMLTag(named tagName: String, in html: String) -> String? {
        htmlTags(named: tagName, in: html).first
    }

    private static func htmlTags(named tagName: String, in html: String) -> [String] {
        let tagPattern = #"(?is)<\#(tagName)\b[^>]*>"#
        guard
            let tagRegex = try? NSRegularExpression(pattern: tagPattern, options: [.caseInsensitive]),
            tagRegex.numberOfMatches(
                in: html,
                options: [],
                range: NSRange(location: 0, length: (html as NSString).length)
            ) > 0
        else {
            return []
        }

        let nsHTML = html as NSString
        return tagRegex.matches(
            in: html,
            options: [],
            range: NSRange(location: 0, length: nsHTML.length)
        )
        .map { nsHTML.substring(with: $0.range) }
    }

    private static func firstHTMLBlock(named tagName: String, in html: String) -> String? {
        let blockPattern = #"(?is)<\#(tagName)\b[^>]*>.*?</\#(tagName)\s*>"#
        guard
            let blockRegex = try? NSRegularExpression(pattern: blockPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]),
            let match = blockRegex.firstMatch(
                in: html,
                options: [],
                range: NSRange(location: 0, length: (html as NSString).length)
            )
        else {
            return nil
        }

        return (html as NSString).substring(with: match.range)
    }

    private static func htmlAttribute(named attributeName: String, in html: String) -> String? {
        let attributePattern = #"\b\#(attributeName)\s*=\s*(?:"([^"]*)"|'([^']*)'|([^\s>]+))"#
        guard
            let attributeRegex = try? NSRegularExpression(pattern: attributePattern, options: [.caseInsensitive]),
            let match = attributeRegex.firstMatch(
                in: html,
                options: [],
                range: NSRange(location: 0, length: (html as NSString).length)
            )
        else {
            return nil
        }

        for rangeIndex in 1..<match.numberOfRanges {
            let range = match.range(at: rangeIndex)
            if range.location != NSNotFound {
                return (html as NSString).substring(with: range).decodingHTMLEntities()
            }
        }

        return nil
    }

    private static func stripHTML(_ value: String) -> String {
        removingNonReadableHTMLBlocks(from: value)
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
            .decodingHTMLEntities()
    }

    private static func removingNonReadableHTMLBlocks(from value: String) -> String {
        value.replacingOccurrences(
            of: #"(?is)<(style|script|noscript|svg)\b[^>]*>.*?</\1\s*>"#,
            with: "",
            options: .regularExpression
        )
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

    private static func appendInlineText(
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

    private static func mergedSpans(_ spans: [ArticleScreenTextSpan]) -> [ArticleScreenTextSpan] {
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

    func decodingHTMLEntities() -> String {
        ArticleScreenBodyPayloadNormalizer.decodeHTMLEntities(in: self)
    }
}
