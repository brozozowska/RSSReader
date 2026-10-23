import CloudKit
import Foundation
import SwiftData
import Testing
@testable import RSSReader

@Suite("Infrastructure / AppDependencies / SwiftData Configuration")
@MainActor
struct AppDependenciesSwiftDataConfigurationTests {
    @Test
    func currentSchemaCreatesFreshStoresAndReopensPersistedData() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let partition = AppPersistenceModelPartition.current
        let plan = AppDependencies.makeSwiftDataConfigurationPlan(
            modelPartition: partition,
            isStoredInMemoryOnly: false,
            syncBackedCloudKitPolicy: .disabled
        )
        func openContainer() throws -> ModelContainer {
            let configurations = [plan.syncBackedStore, plan.localOnlyStore].map { store in
                ModelConfiguration(
                    store.name,
                    schema: store.schema,
                    url: directory.appendingPathComponent("\(store.name).store"),
                    cloudKitDatabase: store.cloudKitPolicy.swiftDataDatabase
                )
            }
            return try ModelContainer(for: partition.schema, configurations: configurations)
        }

        let feedID = UUID()
        do {
            let container = try openContainer()
            let context = container.mainContext
            #expect(try AppDependencies.fetchSyncEnablementBootstrapSettings(from: container) == nil)
            context.insert(AppSettings(useiCloudSync: false))
            context.insert(Feed(id: feedID, url: "https://example.invalid/feed", title: "Feed"))
            context.insert(Article(
                feedID: feedID, feedTitle: "Feed", externalID: "entry",
                url: "https://example.invalid/entry", title: "Entry"
            ))
            context.insert(ArticleState(articleExternalID: "entry", feedID: feedID, isStarred: true))
            context.insert(FeedFetchLog(feedID: feedID, status: "success"))
            try context.save()
        }

        let reopened = try openContainer()
        let context = reopened.mainContext
        #expect(try AppDependencies.fetchSyncEnablementBootstrapSettings(from: reopened)?.useiCloudSync == false)
        #expect(try context.fetch(FetchDescriptor<Feed>()).map(\.id) == [feedID])
        #expect(try context.fetch(FetchDescriptor<Article>()).map(\.externalID) == ["entry"])
        #expect(try context.fetch(FetchDescriptor<ArticleState>()).first?.isStarred == true)
        #expect(try context.fetch(FetchDescriptor<FeedFetchLog>()).count == 1)
    }

    @Test
    func appDependenciesBuildSwiftDataConfigurationsWithActiveCloudKitOnlyForSyncBackedStore() throws {
        let configurationPlan = AppDependencies.makeSwiftDataConfigurationPlan(
            modelPartition: AppPersistenceModelPartition.current,
            isStoredInMemoryOnly: false
        )

        let configurationsByName = Dictionary(
            uniqueKeysWithValues: configurationPlan.modelContainerConfigurations.map { ($0.name, $0) }
        )
        let syncBackedConfiguration = try #require(configurationsByName["SyncBackedStore"])
        let localOnlyConfiguration = try #require(configurationsByName["LocalOnlyStore"])
        let syncBackedCloudKitDatabase = String(describing: syncBackedConfiguration.cloudKitDatabase)
        let localOnlyCloudKitDatabase = String(describing: localOnlyConfiguration.cloudKitDatabase)

        #expect(configurationPlan.modelContainerConfigurations.count == 2)
        #expect(
            syncBackedCloudKitDatabase
                .contains("_privateDBName: Optional(\"\(CloudKitContainerConfiguration.containerIdentifier)\")")
        )
        #expect(localOnlyCloudKitDatabase.contains("_none: true"))
        #expect(syncBackedConfiguration.isStoredInMemoryOnly == false)
        #expect(localOnlyConfiguration.isStoredInMemoryOnly == false)
    }

    @Test
    func appDependenciesBuildSwiftDataConfigurationsWithoutCloudKitWhenSyncEnablementResolvesDisabled() throws {
        let configurationPlan = AppDependencies.makeSwiftDataConfigurationPlan(
            modelPartition: AppPersistenceModelPartition.current,
            isStoredInMemoryOnly: false,
            syncBackedCloudKitPolicy: .disabled
        )

        let configurationsByName = Dictionary(
            uniqueKeysWithValues: configurationPlan.modelContainerConfigurations.map { ($0.name, $0) }
        )
        let syncBackedConfiguration = try #require(configurationsByName["SyncBackedStore"])
        let syncBackedCloudKitDatabase = String(describing: syncBackedConfiguration.cloudKitDatabase)

        #expect(syncBackedCloudKitDatabase.contains("_none: true"))
    }
}
