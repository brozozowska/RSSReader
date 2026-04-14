import Foundation

@MainActor
enum ArticleScreenBodyBlock: Equatable {
    case paragraph(String)
    case image(URL)
    case fallbackNotice(String)
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
                blocks.append(contentsOf: renderTextBlock(stripHTML(textSegment)))
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
            blocks.append(contentsOf: renderTextBlock(stripHTML(trailingSegment)))
        }

        return blocks
    }

    private static func renderTextBlock(_ text: String) -> [ArticleScreenBodyBlock] {
        text
            .normalizedParagraphs
            .map(ArticleScreenBodyBlock.paragraph)
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
