import Foundation

enum CrossDeviceSyncReplicatedValue: String, CaseIterable, Hashable, Sendable {
    case sourceStructure
    case articlePayload
    case articleState
}

enum CrossDeviceArticleMaterializationTrigger: String, CaseIterable, Hashable, Sendable {
    case manualRefresh
    case backgroundRefresh
}

struct CrossDeviceReadingScenario: Equatable, Sendable {
    let replicatedValues: Set<CrossDeviceSyncReplicatedValue>
    let articleMaterializationTriggers: Set<CrossDeviceArticleMaterializationTrigger>
    let requiresAppAuthorization: Bool

    static let current = CrossDeviceReadingScenario(
        replicatedValues: [
            .sourceStructure,
            .articlePayload,
            .articleState
        ],
        articleMaterializationTriggers: [
            .manualRefresh,
            .backgroundRefresh
        ],
        requiresAppAuthorization: false
    )

    var syncsSourceStructure: Bool {
        replicatedValues.contains(.sourceStructure)
    }

    var syncsArticleState: Bool {
        replicatedValues.contains(.articleState)
    }

    var syncsArticlePayload: Bool {
        replicatedValues.contains(.articlePayload)
    }

    var usesLocalArticleCache: Bool {
        false
    }

    var keepsArticleImagesLocalOnly: Bool {
        true
    }

    func materializesArticles(after trigger: CrossDeviceArticleMaterializationTrigger) -> Bool {
        articleMaterializationTriggers.contains(trigger)
    }

    var settingsSectionFooter: String {
        "Feeds, folders, articles, and reading state sync across devices. Article images stay cached on each device."
    }
}
