import SwiftData

enum AppPersistenceCloudKitPolicy: Equatable, Sendable {
    case disabled
    case automatic
    case privateContainer(String)

    var swiftDataDatabase: ModelConfiguration.CloudKitDatabase {
        switch self {
        case .disabled:
            return .none
        case .automatic:
            return .automatic
        case .privateContainer(let identifier):
            return .private(identifier)
        }
    }

    var usesCloudKit: Bool {
        switch self {
        case .disabled:
            false
        case .automatic, .privateContainer:
            true
        }
    }
}

struct AppPersistenceStoreConfiguration {
    let name: String
    let modelTypes: [any PersistentModel.Type]
    let isStoredInMemoryOnly: Bool
    let cloudKitPolicy: AppPersistenceCloudKitPolicy

    var schema: Schema {
        Schema(modelTypes)
    }

    var modelConfiguration: ModelConfiguration {
        ModelConfiguration(
            name,
            schema: schema,
            isStoredInMemoryOnly: isStoredInMemoryOnly,
            cloudKitDatabase: cloudKitPolicy.swiftDataDatabase
        )
    }
}

struct AppPersistenceConfigurationPlan {
    let syncBackedStore: AppPersistenceStoreConfiguration
    let localOnlyStore: AppPersistenceStoreConfiguration

    static func make(
        modelPartition: AppPersistenceModelPartition,
        isStoredInMemoryOnly: Bool,
        syncBackedCloudKitPolicy: AppPersistenceCloudKitPolicy = .disabled
    ) -> AppPersistenceConfigurationPlan {
        AppPersistenceConfigurationPlan(
            syncBackedStore: AppPersistenceStoreConfiguration(
                name: "SyncBackedStore",
                modelTypes: modelPartition.syncBackedModels,
                isStoredInMemoryOnly: isStoredInMemoryOnly,
                cloudKitPolicy: syncBackedCloudKitPolicy
            ),
            localOnlyStore: AppPersistenceStoreConfiguration(
                name: "LocalOnlyStore",
                modelTypes: modelPartition.localOnlyModels,
                isStoredInMemoryOnly: isStoredInMemoryOnly,
                cloudKitPolicy: .disabled
            )
        )
    }

    var modelContainerConfigurations: [ModelConfiguration] {
        [
            syncBackedStore.modelConfiguration,
            localOnlyStore.modelConfiguration
        ]
    }
}
