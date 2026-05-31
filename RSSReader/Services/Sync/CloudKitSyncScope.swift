import Foundation

enum CloudKitSyncScopeModel: String, CaseIterable, Hashable, Sendable {
    case feed
    case folder
    case articleState
    case appSettings
    case article
    case feedFetchLog
}

struct CloudKitSyncScope: Equatable, Sendable {
    let syncBackedModels: Set<CloudKitSyncScopeModel>
    let localOnlyModels: Set<CloudKitSyncScopeModel>

    static let current = CloudKitSyncScope(
        syncBackedModels: [
            .feed,
            .folder,
            .articleState,
            .article,
            .appSettings
        ],
        localOnlyModels: [
            .feedFetchLog
        ]
    )

    func syncs(_ model: CloudKitSyncScopeModel) -> Bool {
        syncBackedModels.contains(model)
    }

    func storesLocallyOnly(_ model: CloudKitSyncScopeModel) -> Bool {
        localOnlyModels.contains(model)
    }

    var syncsSourceStructure: Bool {
        syncs(.feed) && syncs(.folder)
    }

    var syncsReadingState: Bool {
        syncs(.articleState)
    }

    var syncsArticlePayload: Bool {
        syncs(.article)
    }

    var syncsAppSettings: Bool {
        syncs(.appSettings)
    }

    var keepsFeedFetchLogsLocalOnly: Bool {
        storesLocallyOnly(.feedFetchLog)
    }

    func settingsSectionFooter(readingScenario: CrossDeviceReadingScenario) -> String {
        let readingStateCopy = readingScenario.settingsSectionFooter
        return "\(readingStateCopy) Settings sync through iCloud too."
    }
}
