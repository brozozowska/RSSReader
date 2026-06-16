import Foundation

enum CrossDeviceSyncReplicatedValue: String, CaseIterable, Hashable, Sendable {
    case feedStructure
    case articlePayload
    case articleState
}

struct CrossDeviceReadingScenario: Equatable, Sendable {
    let replicatedValues: Set<CrossDeviceSyncReplicatedValue>
    let requiresAppAuthorization: Bool

    static let current = CrossDeviceReadingScenario(
        replicatedValues: [
            .feedStructure,
            .articlePayload,
            .articleState
        ],
        requiresAppAuthorization: false
    )

    var syncsFeedStructure: Bool {
        replicatedValues.contains(.feedStructure)
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
