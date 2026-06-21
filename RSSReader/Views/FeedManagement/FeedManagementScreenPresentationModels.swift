import Foundation

enum FeedManagementScreenLaunchContext: Hashable, Sendable {
    case entry
    case editFeed(UUID)
    case editFolder(UUID)
    case organizeFeed(UUID)

    var opensDirectDestination: Bool {
        switch self {
        case .entry:
            return false
        case .editFeed, .editFolder, .organizeFeed:
            return true
        }
    }
}

enum FeedManagementScenarioID: String, CaseIterable, Hashable, Identifiable, Sendable {
    case addFeed
    case createFolder
    case moveFeed

    var id: String { rawValue }
}

enum FeedManagementSectionID: String, Hashable, Identifiable, Sendable {
    case startNew
    case organizeExisting

    var id: String { rawValue }
}

struct FeedManagementScreenSummaryPresentation: Equatable, Sendable {
    let title: String
    let description: String
}

struct FeedManagementScreenSectionPresentation: Identifiable, Equatable, Sendable {
    let id: FeedManagementSectionID
    let title: String
    let footer: String?
    let items: [FeedManagementScreenItemPresentation]
}

struct FeedManagementScreenItemPresentation: Identifiable, Equatable, Sendable {
    let id: FeedManagementScenarioID
    let title: String
    let subtitle: String
    let systemImageName: String
}

enum FeedManagementAddFeedStatusKind: Hashable, Sendable {
    case success
    case warning
    case failure
}

struct FeedManagementAddFeedStatusPresentation: Hashable, Sendable {
    let title: String
    let kind: FeedManagementAddFeedStatusKind
    let detail: String?
}

struct FeedManagementAddFeedPreviewPresentation: Hashable, Sendable {
    let title: String
    let subtitle: String?
    let siteURL: String?
    let iconURL: String?
    let kindTitle: String
    let resolvedFeedURL: String
    let existingFeedNotice: String?
    let diagnosticsSummary: String?
}

struct FeedManagementFolderPlacementOptionPresentation: Identifiable, Hashable, Sendable {
    let placement: FeedManagementFolderPlacement
    let title: String
    let subtitle: String?
    let trailingValue: String?
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

struct FeedManagementAddFeedPresentation: Hashable, Sendable {
    let id: FeedManagementScenarioID = .addFeed
    let title: String
    let summaryTitle: String
    let summaryDescription: String
    let urlInput: String
    let urlPrompt: String
    let displayNameInput: String
    let displayNamePrompt: String
    let displayNameFooter: String
    let showsDisplayNameInput: Bool
    let validationMessage: String?
    let normalizedURL: String?
    let primaryActionTitle: String
    let isPrimaryActionEnabled: Bool
    let isConfirmationActionEnabled: Bool
    let isLoadingPreview: Bool
    let preview: FeedManagementAddFeedPreviewPresentation?
    let placementTitle: String
    let placementDescription: String
    let placementOptions: [FeedManagementFolderPlacementOptionPresentation]
    let createFolderActionTitle: String?
    let status: FeedManagementAddFeedStatusPresentation?
}

enum FeedManagementCreateFolderFeedbackKind: Hashable, Sendable {
    case success
    case failure
}

struct FeedManagementCreateFolderFeedbackPresentation: Hashable, Sendable {
    let kind: FeedManagementCreateFolderFeedbackKind
    let title: String
    let detail: String?
}

struct FeedManagementCreateFolderExistingFolderPresentation: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let sortOrder: Int
    let feedCount: Int
}

struct FeedManagementCreateFolderPresentation: Hashable, Sendable {
    let id: FeedManagementScenarioID = .createFolder
    let title: String
    let summaryTitle: String
    let summaryDescription: String
    let nameInput: String
    let namePrompt: String
    let validationMessage: String?
    let existingFolders: [FeedManagementCreateFolderExistingFolderPresentation]
    let emptyStateTitle: String?
    let emptyStateDescription: String?
    let placementDescription: String
    let primaryActionTitle: String
    let isPrimaryActionEnabled: Bool
    let isSubmitting: Bool
    let feedback: FeedManagementCreateFolderFeedbackPresentation?
}

struct FeedManagementMoveFeedFeedPresentation: Identifiable, Hashable, Sendable {
    let id: UUID
    let title: String
    let subtitle: String
    let currentPlacementTitle: String
    let isSelected: Bool
}

enum FeedManagementMoveFeedFeedbackKind: Hashable, Sendable {
    case success
    case failure
}

struct FeedManagementMoveFeedFeedbackPresentation: Hashable, Sendable {
    let kind: FeedManagementMoveFeedFeedbackKind
    let title: String
    let detail: String?
}

struct FeedManagementMoveFeedPresentation: Hashable, Sendable {
    let id: FeedManagementScenarioID = .moveFeed
    let title: String
    let summaryTitle: String
    let summaryDescription: String
    let feeds: [FeedManagementMoveFeedFeedPresentation]
    let emptyStateTitle: String?
    let emptyStateDescription: String?
    let placementTitle: String
    let placementDescription: String
    let placementOptions: [FeedManagementFolderPlacementOptionPresentation]
    let primaryActionTitle: String
    let isPrimaryActionEnabled: Bool
    let isSubmitting: Bool
    let feedback: FeedManagementMoveFeedFeedbackPresentation?
}

enum FeedManagementScreenDestinationPresentation: Identifiable, Hashable, Sendable {
    case addFeed(FeedManagementAddFeedPresentation)
    case createFolder(FeedManagementCreateFolderPresentation)
    case moveFeed(FeedManagementMoveFeedPresentation)

    var id: FeedManagementScenarioID {
        switch self {
        case .addFeed(let destination):
            destination.id
        case .createFolder(let destination):
            destination.id
        case .moveFeed(let destination):
            destination.id
        }
    }
}

struct FeedManagementScreenViewState: Equatable, Sendable {
    let summary: FeedManagementScreenSummaryPresentation
    let sections: [FeedManagementScreenSectionPresentation]
    let presentedDestination: FeedManagementScreenDestinationPresentation?
}

enum FeedManagementScreenPresentationBuilder {
    static func buildSummary() -> FeedManagementScreenSummaryPresentation {
        FeedManagementScreenSummaryPresentation(
            title: FeedManagementLocalization.summaryTitle,
            description: FeedManagementLocalization.summaryDescription
        )
    }

    static func buildSections() -> [FeedManagementScreenSectionPresentation] {
        [
            FeedManagementScreenSectionPresentation(
                id: .startNew,
                title: FeedManagementLocalization.addSectionTitle,
                footer: FeedManagementLocalization.addSectionFooter,
                items: [
                    item(
                        id: .addFeed,
                        title: FeedManagementLocalization.addFeedTitle,
                        subtitle: FeedManagementLocalization.addFeedSubtitle,
                        systemImageName: "dot.radiowaves.left.and.right"
                    ),
                    item(
                        id: .createFolder,
                        title: FeedManagementLocalization.createFolderTitle,
                        subtitle: FeedManagementLocalization.createFolderSubtitle,
                        systemImageName: "folder.badge.plus"
                    )
                ]
            ),
            FeedManagementScreenSectionPresentation(
                id: .organizeExisting,
                title: FeedManagementLocalization.organizeSectionTitle,
                footer: FeedManagementLocalization.organizeSectionFooter,
                items: [
                    item(
                        id: .moveFeed,
                        title: FeedManagementLocalization.moveFeedTitle,
                        subtitle: FeedManagementLocalization.moveFeedSubtitle,
                        systemImageName: "arrow.left.arrow.right.circle"
                    )
                ]
            )
        ]
    }
    private static func item(
        id: FeedManagementScenarioID,
        title: String,
        subtitle: String,
        systemImageName: String
    ) -> FeedManagementScreenItemPresentation {
        FeedManagementScreenItemPresentation(
            id: id,
            title: title,
            subtitle: subtitle,
            systemImageName: systemImageName
        )
    }
}
