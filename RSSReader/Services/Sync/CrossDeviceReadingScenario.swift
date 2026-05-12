import Foundation

enum CrossDeviceSyncReplicatedValue: String, CaseIterable, Hashable, Sendable {
    case sourceStructure
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

    var usesLocalArticleCache: Bool {
        true
    }

    func materializesArticles(after trigger: CrossDeviceArticleMaterializationTrigger) -> Bool {
        articleMaterializationTriggers.contains(trigger)
    }

    var settingsSectionFooter: String {
        "Feeds, folders, and reading state sync across devices. Articles stay on each device and appear after manual or background refresh."
    }
}
