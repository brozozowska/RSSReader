import Foundation

enum ArticleScreenBodyPayloadKind: Equatable {
    case plainText
    case html
}

struct ArticleScreenBodyPayload: Equatable {
    let kind: ArticleScreenBodyPayloadKind
    let value: String
}

enum ArticleScreenBodyPayloadNormalizer {
    static func normalize(
        _ rawValue: String?,
        preferredKind: ArticleScreenBodyPayloadKind
    ) -> ArticleScreenBodyPayload? {
        guard let rawValue else { return nil }

        let scalarValue = normalizeScalar(rawValue)
        guard scalarValue.isEmpty == false else { return nil }

        let decodedValue = decodeHTMLEntities(in: scalarValue)
        let resolvedKind = resolvedKind(
            rawValue: scalarValue,
            decodedValue: decodedValue,
            preferredKind: preferredKind
        )

        let normalizedValue: String
        switch resolvedKind {
        case .plainText:
            normalizedValue = normalizePlainText(decodedValue)
        case .html:
            normalizedValue = normalizeHTML(decodedValue)
        }

        guard normalizedValue.isEmpty == false else { return nil }
        return ArticleScreenBodyPayload(kind: resolvedKind, value: normalizedValue)
    }

    static func decodeHTMLEntities(in value: String) -> String {
        var decodedValue = value

        for _ in 0..<3 {
            let nextValue = decodeHTMLEntitiesOnce(in: decodedValue)
            guard nextValue != decodedValue else { break }
            decodedValue = nextValue
        }

        return decodedValue
    }

    private static func resolvedKind(
        rawValue: String,
        decodedValue: String,
        preferredKind: ArticleScreenBodyPayloadKind
    ) -> ArticleScreenBodyPayloadKind {
        if containsHTMLTag(decodedValue) || containsEscapedHTMLTag(rawValue) {
            return .html
        }

        return preferredKind
    }

    private static func normalizeScalar(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizePlainText(_ value: String) -> String {
        let paragraphs = value.components(separatedBy: "\n\n")
        let normalizedParagraphs = paragraphs.compactMap { paragraph -> String? in
            let normalizedLines = paragraph
                .components(separatedBy: .newlines)
                .map(normalizeInlineWhitespace)
                .filter { $0.isEmpty == false }

            let normalizedParagraph = normalizedLines.joined(separator: " ")
            return normalizedParagraph.isEmpty ? nil : normalizedParagraph
        }

        return normalizedParagraphs.joined(separator: "\n\n")
    }

    nonisolated private static func normalizeInlineWhitespace(_ value: String) -> String {
        value
            .components(separatedBy: .whitespaces)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")
    }

    private static func normalizeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(
                of: #">\s+<"#,
                with: "><",
                options: .regularExpression
            )
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func containsHTMLTag(_ value: String) -> Bool {
        value.range(
            of: #"<\s*/?\s*(a|article|blockquote|br|code|div|em|figcaption|figure|h[1-6]|hr|iframe|img|li|ol|p|picture|pre|section|source|span|strong|table|tbody|td|th|thead|tr|ul|video|audio)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func containsEscapedHTMLTag(_ value: String) -> Bool {
        value.range(
            of: #"&lt;\s*/?\s*(a|article|blockquote|br|code|div|em|figcaption|figure|h[1-6]|hr|iframe|img|li|ol|p|picture|pre|section|source|span|strong|table|tbody|td|th|thead|tr|ul|video|audio)\b"#,
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private static func decodeHTMLEntitiesOnce(in value: String) -> String {
        var decodedValue = ""
        var currentIndex = value.startIndex

        while currentIndex < value.endIndex {
            guard value[currentIndex] == "&",
                  let semicolonIndex = value[currentIndex...].firstIndex(of: ";")
            else {
                decodedValue.append(value[currentIndex])
                currentIndex = value.index(after: currentIndex)
                continue
            }

            let entityStartIndex = value.index(after: currentIndex)
            let entity = String(value[entityStartIndex..<semicolonIndex])

            if let decodedEntity = decodeEntity(entity) {
                decodedValue.append(decodedEntity)
                currentIndex = value.index(after: semicolonIndex)
            } else {
                decodedValue.append(value[currentIndex])
                currentIndex = value.index(after: currentIndex)
            }
        }

        return decodedValue
    }

    private static func decodeEntity(_ entity: String) -> String? {
        if entity.hasPrefix("#x") || entity.hasPrefix("#X") {
            return decodeNumericEntity(String(entity.dropFirst(2)), radix: 16)
        }

        if entity.hasPrefix("#") {
            return decodeNumericEntity(String(entity.dropFirst()), radix: 10)
        }

        return namedHTMLEntities[entity.lowercased()]
    }

    private static func decodeNumericEntity(_ value: String, radix: Int) -> String? {
        guard let scalarValue = UInt32(value, radix: radix),
              let scalar = UnicodeScalar(scalarValue)
        else {
            return nil
        }

        return String(Character(scalar))
    }

    private static let namedHTMLEntities: [String: String] = [
        "amp": "&",
        "apos": "'",
        "bull": "•",
        "copy": "©",
        "gt": ">",
        "hellip": "...",
        "laquo": "«",
        "lt": "<",
        "mdash": "—",
        "ndash": "–",
        "nbsp": " ",
        "quot": "\"",
        "raquo": "»",
        "reg": "®",
        "rsquo": "’",
        "trade": "™"
    ]
}
