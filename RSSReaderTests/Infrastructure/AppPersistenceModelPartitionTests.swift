import SwiftData
import Testing
@testable import RSSReader

@Suite("Infrastructure / Persistence Model Partition")
@MainActor
struct AppPersistenceModelPartitionTests {
    @Test
    func persistenceModelPartitionMatchesCloudKitSyncScope() {
        let partition = AppPersistenceModelPartition.current
        let scope = CloudKitSyncScope.current

        #expect(partition.syncBackedScopeModels == scope.syncBackedModels)
        #expect(partition.localOnlyScopeModels == scope.localOnlyModels)
    }

    @Test
    func persistenceModelPartitionSyncsArticleAndKeepsFeedFetchLogLocalOnly() {
        let partition = AppPersistenceModelPartition.current

        #expect(
            modelTypeNames(partition.localOnlyModels)
                == modelTypeNames([FeedFetchLog.self])
        )
        #expect(
            modelTypeNames(partition.syncBackedModels)
                == modelTypeNames([AppSettings.self, ArticleState.self, Article.self, Feed.self, Folder.self])
        )
    }

    @Test
    func appCompositionExposesCombinedPersistenceModelsFromPartition() {
        let partition = AppComposition.persistenceModelPartition

        #expect(modelTypeNames(AppComposition.syncBackedModels) == modelTypeNames(partition.syncBackedModels))
        #expect(modelTypeNames(AppComposition.localOnlyModels) == modelTypeNames(partition.localOnlyModels))
        #expect(modelTypeNames(AppComposition.appModels) == modelTypeNames(partition.allModels))
    }

    @Test
    func persistenceConfigurationPlanBuildsExplicitSyncAndLocalStores() {
        let plan = AppPersistenceConfigurationPlan.make(
            modelPartition: AppPersistenceModelPartition.current,
            isStoredInMemoryOnly: false
        )

        #expect(
            modelTypeNames(plan.syncBackedStore.modelTypes)
                == modelTypeNames([AppSettings.self, ArticleState.self, Article.self, Feed.self, Folder.self])
        )
        #expect(
            modelTypeNames(plan.localOnlyStore.modelTypes)
                == modelTypeNames([FeedFetchLog.self])
        )
        #expect(plan.syncBackedStore.cloudKitPolicy == .disabled)
        #expect(plan.localOnlyStore.cloudKitPolicy == .disabled)
        #expect(plan.modelContainerConfigurations.count == 2)
    }

    @Test
    func persistenceConfigurationPlanAcceptsExplicitPrivateCloudKitPolicyForSyncBackedStore() {
        let plan = AppPersistenceConfigurationPlan.make(
            modelPartition: AppPersistenceModelPartition.current,
            isStoredInMemoryOnly: false,
            syncBackedCloudKitPolicy: CloudKitContainerConfiguration.syncBackedDatabasePolicy
        )

        #expect(
            plan.syncBackedStore.cloudKitPolicy
                == .privateContainer(CloudKitContainerConfiguration.containerIdentifier)
        )
        #expect(plan.localOnlyStore.cloudKitPolicy == .disabled)
    }

    private func modelTypeNames(_ models: [any PersistentModel.Type]) -> [String] {
        models.map { String(reflecting: $0) }
    }
}
