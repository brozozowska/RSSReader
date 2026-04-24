import SwiftData

struct AppPersistenceModelDescriptor {
    let scopeModel: CloudKitSyncScopeModel
    let persistentModelType: any PersistentModel.Type
}

struct AppPersistenceModelPartition {
    let syncBackedEntries: [AppPersistenceModelDescriptor]
    let localOnlyEntries: [AppPersistenceModelDescriptor]

    static let current = AppPersistenceModelPartition(
        syncBackedEntries: [
            AppPersistenceModelDescriptor(
                scopeModel: .appSettings,
                persistentModelType: AppSettings.self
            ),
            AppPersistenceModelDescriptor(
                scopeModel: .articleState,
                persistentModelType: ArticleState.self
            ),
            AppPersistenceModelDescriptor(
                scopeModel: .feed,
                persistentModelType: Feed.self
            ),
            AppPersistenceModelDescriptor(
                scopeModel: .folder,
                persistentModelType: Folder.self
            )
        ],
        localOnlyEntries: [
            AppPersistenceModelDescriptor(
                scopeModel: .article,
                persistentModelType: Article.self
            ),
            AppPersistenceModelDescriptor(
                scopeModel: .feedFetchLog,
                persistentModelType: FeedFetchLog.self
            )
        ]
    )

    var syncBackedModels: [any PersistentModel.Type] {
        syncBackedEntries.map { $0.persistentModelType }
    }

    var localOnlyModels: [any PersistentModel.Type] {
        localOnlyEntries.map { $0.persistentModelType }
    }

    var allModels: [any PersistentModel.Type] {
        syncBackedModels + localOnlyModels
    }

    var syncBackedScopeModels: Set<CloudKitSyncScopeModel> {
        Set(syncBackedEntries.map { $0.scopeModel })
    }

    var localOnlyScopeModels: Set<CloudKitSyncScopeModel> {
        Set(localOnlyEntries.map { $0.scopeModel })
    }

    var schema: Schema {
        Schema(allModels)
    }
}
