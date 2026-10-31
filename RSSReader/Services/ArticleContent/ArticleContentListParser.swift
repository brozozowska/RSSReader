import Foundation

extension ArticleContentBodyPayloadRenderer {
    nonisolated static func renderHTMLList(
        _ innerHTML: String,
        kind: ArticleContentListKind,
        article: ReaderArticleDTO
    ) -> [ArticleContentBodyBlock] {
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
        .compactMap { match -> ArticleContentTextBlock? in
            let itemHTML = nsHTML.substring(with: match.range(at: 1))
            return makeTextBlock(fromHTML: itemHTML, article: article)
        }

        return items.isEmpty ? [] : [.list(ArticleContentListBlock(kind: kind, items: items))]
    }

    nonisolated static func renderHTMLDefinitionList(
        _ innerHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleContentBodyBlock] {
        let itemPattern = #"(?is)<(dt|dd)\b[^>]*>(.*?)</\1\s*>"#
        guard let itemRegex = try? NSRegularExpression(pattern: itemPattern) else {
            return renderHTMLDefinitionListFallback(innerHTML, article: article)
        }

        let nsHTML = innerHTML as NSString
        let matches = itemRegex.matches(
            in: innerHTML,
            range: NSRange(location: 0, length: nsHTML.length)
        )
        let openingItemCount = innerHTML.lowercased().matches(of: /<(?:dt|dd)\b/).count
        guard matches.isEmpty == false, matches.count == openingItemCount else {
            return renderHTMLDefinitionListFallback(innerHTML, article: article)
        }

        var entries: [ArticleContentDefinitionEntry] = []
        var currentTerm: ArticleContentTextBlock?
        var currentDefinitions: [ArticleContentTextBlock?] = []
        var hasCurrentEntry = false

        func appendCurrentEntry() {
            guard hasCurrentEntry else { return }
            entries.append(
                ArticleContentDefinitionEntry(
                    term: currentTerm,
                    definitions: currentDefinitions
                )
            )
        }

        for match in matches {
            let tagName = nsHTML.substring(with: match.range(at: 1)).lowercased()
            let content = makeTextBlock(
                fromHTML: nsHTML.substring(with: match.range(at: 2)),
                article: article
            )

            if tagName == "dt" {
                appendCurrentEntry()
                currentTerm = content
                currentDefinitions = []
                hasCurrentEntry = true
            } else {
                if hasCurrentEntry == false {
                    hasCurrentEntry = true
                }
                currentDefinitions.append(content)
            }
        }
        appendCurrentEntry()

        guard entries.isEmpty == false else {
            return renderHTMLDefinitionListFallback(innerHTML, article: article)
        }
        return [.definitionList(ArticleContentDefinitionListBlock(entries: entries))]
    }

    nonisolated static func renderHTMLDefinitionListFallback(
        _ innerHTML: String,
        article: ReaderArticleDTO
    ) -> [ArticleContentBodyBlock] {
        let fallbackHTML = innerHTML.replacingOccurrences(
            of: #"(?i)</(dt|dd)\s*>"#,
            with: "\n\n",
            options: .regularExpression
        )
        return renderHTMLTextSegment(fallbackHTML, article: article)
    }
}
