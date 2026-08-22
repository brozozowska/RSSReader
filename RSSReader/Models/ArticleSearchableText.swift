import Foundation

nonisolated enum ArticleSearchQueryNormalizationPolicy {
    static let maximumUTF8ByteCount = ArticleSearchableTextPolicy.maximumUTF8ByteCount

    static func normalize(_ query: String) -> String {
        ArticleSearchTextNormalization.normalizedWhitespace(
            query,
            maximumSourceUTF8ByteCount: maximumUTF8ByteCount
        )
    }
}

nonisolated enum ArticleSearchableTextPolicy {
    static let maximumUTF8ByteCount = 16 * 1_024
    private static let maximumSourceUTF8ByteCount = 64 * 1_024

    static func materialize(
        title: String,
        summary: String?,
        contentHTML: String?,
        contentText: String?,
        author: String?
    ) -> String {
        var result = ""

        append(title, to: &result)
        append(summary, to: &result)
        append(contentText, to: &result)
        append(author, to: &result)
        append(plainTextFallback(fromHTML: contentHTML), to: &result)

        return result
    }

    private static func append(_ value: String?, to result: inout String) {
        guard result.utf8.count < maximumUTF8ByteCount,
              let normalizedValue = normalizedPlainText(value),
              normalizedValue.isEmpty == false else {
            return
        }

        let separator = result.isEmpty ? "" : " "
        let remainingByteCount = maximumUTF8ByteCount - result.utf8.count
        guard remainingByteCount > separator.utf8.count else { return }

        let boundedValue = ArticleSearchTextNormalization.boundedUTF8Prefix(
            normalizedValue,
            maximumByteCount: remainingByteCount - separator.utf8.count
        )
        guard boundedValue.isEmpty == false else { return }

        result += separator
        result += boundedValue
    }

    private static func normalizedPlainText(_ value: String?) -> String? {
        guard let value else { return nil }

        let normalizedValue = ArticleSearchTextNormalization.normalizedWhitespace(
            value,
            maximumSourceUTF8ByteCount: maximumSourceUTF8ByteCount
        )

        return normalizedValue.isEmpty ? nil : normalizedValue
    }

    private static func plainTextFallback(fromHTML html: String?) -> String? {
        guard let html else { return nil }

        let boundedHTML = ArticleSearchTextNormalization.boundedUTF8Prefix(
            html,
            maximumByteCount: maximumSourceUTF8ByteCount
        )
        return boundedHTML
            .replacingOccurrences(of: #"(?i)<br\s*/?>"#, with: " ", options: .regularExpression)
            .replacingOccurrences(
                of: #"(?i)</?(p|div|section|article|blockquote|ul|ol|li|h[1-6]|pre|figure|figcaption|table|tbody|thead|tr|td|th)\b[^>]*>"#,
                with: " ",
                options: .regularExpression
            )
            .replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .decodingBasicHTMLEntities()
    }
}

private nonisolated enum ArticleSearchTextNormalization {
    static func normalizedWhitespace(
        _ value: String,
        maximumSourceUTF8ByteCount: Int
    ) -> String {
        boundedUTF8Prefix(
            value,
            maximumByteCount: maximumSourceUTF8ByteCount
        )
        .precomposedStringWithCanonicalMapping
        .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func boundedUTF8Prefix(
        _ value: String,
        maximumByteCount: Int
    ) -> String {
        guard maximumByteCount > 0 else { return "" }
        guard value.utf8.count > maximumByteCount else { return value }

        var result = ""
        var byteCount = 0
        for character in value {
            let characterByteCount = String(character).utf8.count
            guard byteCount + characterByteCount <= maximumByteCount else { break }
            result.append(character)
            byteCount += characterByteCount
        }
        return result
    }
}

private extension String {
    nonisolated func decodingBasicHTMLEntities() -> String {
        replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&apos;", with: "'")
    }
}
