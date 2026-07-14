import Foundation

nonisolated enum FeedTextHTMLNormalizer {
    static func normalizeScalar(_ value: String?) -> String? {
        guard let value else { return nil }

        let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedValue.isEmpty == false else { return nil }
        return normalizedValue
    }

    static func normalizeInlineText(_ value: String?) -> String? {
        guard let value = normalizeScalar(value) else { return nil }

        let collapsedValue = value
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { $0.isEmpty == false }
            .joined(separator: " ")

        return collapsedValue.isEmpty ? nil : collapsedValue
    }

    static func normalizeTitle(_ value: String?) -> String? {
        guard let value = normalizeScalar(value) else { return nil }

        let decodedValue = decodeHTMLEntities(in: value)
        let textValue = stripHTML(decodedValue)
        guard let value = normalizeInlineText(removeInvisibleCharacters(from: textValue)) else { return nil }

        let normalizedValue = value
            .replacingOccurrences(of: " ,", with: ",")
            .replacingOccurrences(of: " .", with: ".")
            .replacingOccurrences(of: " !", with: "!")
            .replacingOccurrences(of: " ?", with: "?")
            .replacingOccurrences(of: " :", with: ":")
            .replacingOccurrences(of: " ;", with: ";")

        return normalizedValue.isEmpty ? nil : normalizedValue
    }

    static func normalizeAuthor(_ value: String?) -> String? {
        guard let value = normalizeInlineText(value) else { return nil }

        let authorWithoutWrappedEmail = value.replacingOccurrences(
            of: #"\s*[\(<\[]\s*(?:mailto:)?[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\s*[\)>\]]\s*"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )
        let authorWithoutEmail = authorWithoutWrappedEmail.replacingOccurrences(
            of: #"\b(?:mailto:)?[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b"#,
            with: " ",
            options: [.regularExpression, .caseInsensitive]
        )

        return normalizeInlineText(authorWithoutEmail)
    }

    static func normalizeTextBlock(_ value: String?) -> String? {
        guard let value = normalizeScalar(value) else { return nil }

        let lines = value
            .components(separatedBy: .newlines)
            .map { line in
                line
                    .components(separatedBy: .whitespaces)
                    .filter { $0.isEmpty == false }
                    .joined(separator: " ")
            }

        let normalizedValue = lines
            .drop(while: { $0.isEmpty })
            .reversed()
            .drop(while: { $0.isEmpty })
            .reversed()
            .joined(separator: "\n")

        return normalizedValue.isEmpty ? nil : normalizedValue
    }

    static func normalizeTextContent(_ value: String?) -> String? {
        normalizeTextBlock(value)?
            .replacingOccurrences(of: "\u{00A0}", with: " ")
    }

    static func normalizeHTMLContent(_ value: String?) -> String? {
        guard let value = normalizeScalar(value) else { return nil }

        let normalizedValue = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return normalizedValue.isEmpty ? nil : normalizedValue
    }

    private static func decodeHTMLEntities(in value: String) -> String {
        var decodedValue = value

        for _ in 0..<3 {
            let nextValue = decodeHTMLEntitiesOnce(in: decodedValue)
            guard nextValue != decodedValue else { break }
            decodedValue = nextValue
        }

        return decodedValue
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
        guard let scalarValue = UInt32(value, radix: radix) else {
            return nil
        }

        if let legacyCharacter = legacyC1HTMLEntities[scalarValue] {
            return legacyCharacter
        }

        guard let scalar = UnicodeScalar(scalarValue) else {
            return nil
        }

        return String(Character(scalar))
    }

    private static func stripHTML(_ value: String) -> String {
        value
            .replacingOccurrences(
                of: #"<[^>]+>"#,
                with: " ",
                options: [.regularExpression, .caseInsensitive]
            )
    }

    private static func removeInvisibleCharacters(from value: String) -> String {
        var normalizedValue = ""

        for scalar in value.unicodeScalars {
            if scalar.value == 0x00A0 {
                normalizedValue.append(" ")
                continue
            }

            switch scalar.properties.generalCategory {
            case .control, .format, .surrogate, .privateUse, .unassigned:
                continue
            default:
                normalizedValue.unicodeScalars.append(scalar)
            }
        }

        return normalizedValue
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

    private static let legacyC1HTMLEntities: [UInt32: String] = [
        128: "€",
        130: "‚",
        131: "ƒ",
        132: "„",
        133: "...",
        134: "†",
        135: "‡",
        136: "ˆ",
        137: "‰",
        138: "Š",
        139: "‹",
        140: "Œ",
        142: "Ž",
        145: "‘",
        146: "’",
        147: "“",
        148: "”",
        149: "•",
        150: "–",
        151: "—",
        152: "˜",
        153: "™",
        154: "š",
        155: "›",
        156: "œ",
        158: "ž",
        159: "Ÿ"
    ]
}
