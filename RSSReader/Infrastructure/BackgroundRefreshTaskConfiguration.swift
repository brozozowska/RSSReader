import Foundation

enum BackgroundRefreshTaskConfiguration {
    nonisolated static let permittedIdentifiersInfoPlistKey = "BGTaskSchedulerPermittedIdentifiers"
    nonisolated static let appRefreshIdentifier = "ru.brozozowska.RSSReader.background-refresh"
    nonisolated static let permittedIdentifiers = [appRefreshIdentifier]
}
