import Foundation

enum BackgroundRefreshTaskConfiguration {
    static let permittedIdentifiersInfoPlistKey = "BGTaskSchedulerPermittedIdentifiers"
    static let appRefreshIdentifier = "ru.brozozowska.RSSReader.background-refresh"
    static let permittedIdentifiers = [appRefreshIdentifier]
}
