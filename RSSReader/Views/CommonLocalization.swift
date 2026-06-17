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

    static func localizedCountTemplate(_ template: String, count: Int) -> String {
        String.localizedStringWithFormat(template, Int64(count))
    }
}
