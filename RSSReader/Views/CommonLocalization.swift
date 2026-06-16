import Foundation

enum CommonLocalization {
    static let cancelAction = String(
        localized: "common.action.cancel",
        defaultValue: "Cancel",
        comment: "Generic cancel action title."
    )
    static let retryAction = String(
        localized: "common.action.retry",
        defaultValue: "Retry",
        comment: "Generic retry action title."
    )

    static func localizedTemplate(_ template: String, _ arguments: CVarArg...) -> String {
        withVaList(arguments) { argumentList in
            NSString(
                format: template,
                locale: Locale.autoupdatingCurrent,
                arguments: argumentList
            ) as String
        }
    }

    static func formattedInteger(_ value: Int, locale: Locale = .autoupdatingCurrent) -> String {
        value.formatted(.number.locale(locale))
    }
}

struct LocalizedPluralTemplates {
    let one: String
    let few: String
    let many: String
    let other: String

    func template(for count: Int, locale: Locale = .autoupdatingCurrent) -> String {
        switch category(for: count, locale: locale) {
        case .one:
            one
        case .few:
            few
        case .many:
            many
        case .other:
            other
        }
    }

    func string(for count: Int, locale: Locale = .autoupdatingCurrent) -> String {
        CommonLocalization.localizedTemplate(
            template(for: count, locale: locale),
            CommonLocalization.formattedInteger(count, locale: locale)
        )
    }

    private func category(for count: Int, locale: Locale) -> LocalizedPluralCategory {
        guard locale.usesRussianPluralRules else {
            return count == 1 ? .one : .other
        }

        let absoluteCount = abs(count)
        let mod10 = absoluteCount % 10
        let mod100 = absoluteCount % 100

        if mod10 == 1 && mod100 != 11 {
            return .one
        }

        if (2...4).contains(mod10) && !(12...14).contains(mod100) {
            return .few
        }

        if mod10 == 0 || (5...9).contains(mod10) || (11...14).contains(mod100) {
            return .many
        }

        return .other
    }
}

private enum LocalizedPluralCategory {
    case one
    case few
    case many
    case other
}

private extension Locale {
    var usesRussianPluralRules: Bool {
        let languageIdentifier = identifier
            .split(separator: "_", maxSplits: 1)
            .first?
            .split(separator: "-", maxSplits: 1)
            .first

        return languageIdentifier == "ru"
    }
}
