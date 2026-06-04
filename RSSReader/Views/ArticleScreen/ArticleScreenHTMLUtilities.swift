import Foundation

extension ArticleScreenBodyPayloadRenderer {
    static func leadingTagName(in html: String) -> String {
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

    static func unwrapHTMLBlock(_ html: String) -> String {
        html
            .replacingOccurrences(of: #"(?is)^<[^>]+>"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"(?is)</[^>]+>\s*$"#, with: "", options: .regularExpression)
    }

    static func firstHTMLTag(named tagName: String, in html: String) -> String? {
        htmlTags(named: tagName, in: html).first
    }

    static func htmlTags(named tagName: String, in html: String) -> [String] {
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

    static func firstHTMLBlock(named tagName: String, in html: String) -> String? {
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

    static func htmlAttribute(named attributeName: String, in html: String) -> String? {
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
                return (html as NSString).substring(with: range).articleScreenDecodingHTMLEntities()
            }
        }

        return nil
    }

    static func stripHTML(_ value: String) -> String {
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
            .articleScreenDecodingHTMLEntities()
    }

    static func removingNonReadableHTMLBlocks(from value: String) -> String {
        value.replacingOccurrences(
            of: #"(?is)<(style|script|noscript|svg)\b[^>]*>.*?</\1\s*>"#,
            with: "",
            options: .regularExpression
        )
    }
}

extension Array where Element == ArticleScreenBodyBlock {
    var containsImageBlock: Bool {
        contains {
            if case .image = $0 {
                return true
            }
            return false
        }
    }
}

extension String {
    var articleScreenNilIfBlank: String? {
        let trimmedValue = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedValue.isEmpty ? nil : trimmedValue
    }

    var articleScreenNormalizedParagraphs: [String] {
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

    func articleScreenDecodingHTMLEntities() -> String {
        ArticleScreenBodyPayloadNormalizer.decodeHTMLEntities(in: self)
    }
}
