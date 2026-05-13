import Foundation

enum SourceManagementScreenLaunchContext: Hashable, Sendable {
    case entry
    case editFeed(UUID)
    case editFolder(UUID)
}

enum SourceManagementScenarioID: String, CaseIterable, Hashable, Identifiable, Sendable {
    case addFeed
    case createFolder
    case moveSource

    var id: String { rawValue }
}

enum SourceManagementSectionID: String, Hashable, Identifiable, Sendable {
    case startNew
    case organizeExisting

    var id: String { rawValue }
}

struct SourceManagementScreenSummaryPresentation: Equatable, Sendable {
    let title: String
    let description: String
}

struct SourceManagementScreenSectionPresentation: Identifiable, Equatable, Sendable {
    let id: SourceManagementSectionID
    let title: String
    let footer: String?
    let items: [SourceManagementScreenItemPresentation]
}

struct SourceManagementScreenItemPresentation: Identifiable, Equatable, Sendable {
    let id: SourceManagementScenarioID
    let title: String
    let subtitle: String
    let systemImageName: String
    let badgeTitle: String
}

enum SourceManagementAddFeedStatusKind: Hashable, Sendable {
    case success
    case warning
    case failure
}

struct SourceManagementAddFeedStatusPresentation: Hashable, Sendable {
    let title: String
    let kind: SourceManagementAddFeedStatusKind
    let detail: String?
}

struct SourceManagementAddFeedPreviewPresentation: Hashable, Sendable {
    let title: String
    let subtitle: String?
    let siteURL: String?
    let iconURL: String?
    let kindTitle: String
    let resolvedFeedURL: String
    let existingFeedNotice: String?
    let diagnosticsSummary: String?
}

struct SourceManagementFolderPlacementOptionPresentation: Identifiable, Hashable, Sendable {
    let placement: SourceManagementFolderPlacement
    let title: String
    let subtitle: String?
    let isSelected: Bool

    var id: String {
        switch placement {
        case .ungrouped:
            return "ungrouped"
        case .folder(let folderID):
            return folderID.uuidString
        }
    }
}

struct SourceManagementAddFeedPresentation: Hashable, Sendable {
    let id: SourceManagementScenarioID = .addFeed
    let title: String
    let summaryTitle: String
    let summaryDescription: String
    let urlInput: String
    let urlPrompt: String
    let validationMessage: String?
    let normalizedURL: String?
    let primaryActionTitle: String
    let isPrimaryActionEnabled: Bool
    let isConfirmationActionEnabled: Bool
    let isLoadingPreview: Bool
    let preview: SourceManagementAddFeedPreviewPresentation?
    let placementTitle: String
    let placementDescription: String
    let placementOptions: [SourceManagementFolderPlacementOptionPresentation]
    let createFolderActionTitle: String?
    let status: SourceManagementAddFeedStatusPresentation?
}

enum SourceManagementCreateFolderFeedbackKind: Hashable, Sendable {
    case success
    case failure
}

struct SourceManagementCreateFolderFeedbackPresentation: Hashable, Sendable {
    let kind: SourceManagementCreateFolderFeedbackKind
    let title: String
    let detail: String?
}

struct SourceManagementCreateFolderExistingFolderPresentation: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let sortOrder: Int
    let feedCount: Int
}

struct SourceManagementCreateFolderPresentation: Hashable, Sendable {
    let id: SourceManagementScenarioID = .createFolder
    let title: String
    let summaryTitle: String
    let summaryDescription: String
    let nameInput: String
    let namePrompt: String
    let validationMessage: String?
    let existingFolders: [SourceManagementCreateFolderExistingFolderPresentation]
    let emptyStateTitle: String?
    let emptyStateDescription: String?
    let placementDescription: String
    let primaryActionTitle: String
    let isPrimaryActionEnabled: Bool
    let isSubmitting: Bool
    let feedback: SourceManagementCreateFolderFeedbackPresentation?
}

struct SourceManagementMoveSourceFeedPresentation: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String
    let currentPlacementTitle: String
    let isSelected: Bool
}

enum SourceManagementMoveSourceFeedbackKind: Hashable, Sendable {
    case success
    case failure
}

struct SourceManagementMoveSourceFeedbackPresentation: Hashable, Sendable {
    let kind: SourceManagementMoveSourceFeedbackKind
    let title: String
    let detail: String?
}

struct SourceManagementMoveSourcePresentation: Hashable, Sendable {
    let id: SourceManagementScenarioID = .moveSource
    let title: String
    let summaryTitle: String
    let summaryDescription: String
    let feeds: [SourceManagementMoveSourceFeedPresentation]
    let emptyStateTitle: String?
    let emptyStateDescription: String?
    let placementTitle: String
    let placementDescription: String
    let placementOptions: [SourceManagementFolderPlacementOptionPresentation]
    let primaryActionTitle: String
    let isPrimaryActionEnabled: Bool
    let isSubmitting: Bool
    let feedback: SourceManagementMoveSourceFeedbackPresentation?
}

enum SourceManagementScreenDestinationPresentation: Identifiable, Hashable, Sendable {
    case addFeed(SourceManagementAddFeedPresentation)
    case createFolder(SourceManagementCreateFolderPresentation)
    case moveSource(SourceManagementMoveSourcePresentation)

    var id: SourceManagementScenarioID {
        switch self {
        case .addFeed(let destination):
            destination.id
        case .createFolder(let destination):
            destination.id
        case .moveSource(let destination):
            destination.id
        }
    }
}

struct SourceManagementScreenViewState: Equatable, Sendable {
    let summary: SourceManagementScreenSummaryPresentation
    let sections: [SourceManagementScreenSectionPresentation]
    let presentedDestination: SourceManagementScreenDestinationPresentation?
}

enum SourceManagementScreenPresentationBuilder {
    static func buildSummary() -> SourceManagementScreenSummaryPresentation {
        SourceManagementScreenSummaryPresentation(
            title: "Manage sources and folders.",
            description: "Add new feeds, create folders, or move existing sources when your reading list needs a different structure."
        )
    }

    static func buildSections() -> [SourceManagementScreenSectionPresentation] {
        [
            SourceManagementScreenSectionPresentation(
                id: .startNew,
                title: "Add",
                footer: "Start with a feed address, or create a folder first if you already know how you want to organize sources.",
                items: [
                    item(
                        id: .addFeed,
                        title: "Add Feed",
                        subtitle: "Find a feed, review its details, and choose where it belongs.",
                        systemImageName: "dot.radiowaves.left.and.right",
                        badgeTitle: "New Feed"
                    ),
                    item(
                        id: .createFolder,
                        title: "Create Folder",
                        subtitle: "Group related sources under a folder name that is easy to scan.",
                        systemImageName: "folder.badge.plus",
                        badgeTitle: "New Folder"
                    )
                ]
            ),
            SourceManagementScreenSectionPresentation(
                id: .organizeExisting,
                title: "Organize",
                footer: "Move saved feeds between folders without adding them again.",
                items: [
                    item(
                        id: .moveSource,
                        title: "Move Sources",
                        subtitle: "Change where an existing feed appears in your source list.",
                        systemImageName: "arrow.left.arrow.right.circle",
                        badgeTitle: "Existing Sources"
                    )
                ]
            )
        ]
    }
    private static func item(
        id: SourceManagementScenarioID,
        title: String,
        subtitle: String,
        systemImageName: String,
        badgeTitle: String
    ) -> SourceManagementScreenItemPresentation {
        SourceManagementScreenItemPresentation(
            id: id,
            title: title,
            subtitle: subtitle,
            systemImageName: systemImageName,
            badgeTitle: badgeTitle
        )
    }
}
