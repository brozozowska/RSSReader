import Foundation

enum CrossDeviceSyncReplicatedValue: String, CaseIterable, Hashable, Sendable {
    case sourceStructure
    case articlePayload
    case articleState
}

struct CrossDeviceReadingScenario: Equatable, Sendable {
    let replicatedValues: Set<CrossDeviceSyncReplicatedValue>
    let requiresAppAuthorization: Bool

    static let current = CrossDeviceReadingScenario(
        replicatedValues: [
            .sourceStructure,
            .articlePayload,
            .articleState
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

    var keepsArticleImagesLocalOnly: Bool {
        true
    }

    var settingsSectionFooter: String {
        "Feeds, folders, articles, and reading state sync across devices. Article images stay cached on each device."
    }
}
