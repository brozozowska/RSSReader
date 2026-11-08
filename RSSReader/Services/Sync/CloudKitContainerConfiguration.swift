import Foundation

enum CloudKitContainerConfiguration {
    nonisolated static let containerIdentifier = "iCloud.ru.brozozowska.RSSReader"
    static let syncBackedDatabasePolicy: AppPersistenceCloudKitPolicy = .privateContainer(containerIdentifier)
}
