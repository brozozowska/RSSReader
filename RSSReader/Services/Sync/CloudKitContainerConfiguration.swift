import Foundation

enum CloudKitContainerConfiguration {
    static let containerIdentifier = "iCloud.ru.brozozowska.RSSReader"
    static let syncBackedDatabasePolicy: AppPersistenceCloudKitPolicy = .privateContainer(containerIdentifier)
}
