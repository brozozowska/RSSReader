import Foundation

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

struct SourceManagementScenarioPlaceholderPresentation: Identifiable, Hashable, Sendable {
    let id: SourceManagementScenarioID
    let title: String
    let summaryTitle: String
    let summaryDescription: String
    let steps: [String]
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
    let placementDescription: String
    let primaryActionTitle: String
    let isPrimaryActionEnabled: Bool
    let isSubmitting: Bool
    let feedback: SourceManagementCreateFolderFeedbackPresentation?
}

enum SourceManagementScreenDestinationPresentation: Identifiable, Hashable, Sendable {
    case placeholder(SourceManagementScenarioPlaceholderPresentation)
    case createFolder(SourceManagementCreateFolderPresentation)

    var id: SourceManagementScenarioID {
        switch self {
        case .placeholder(let destination):
            destination.id
        case .createFolder(let destination):
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
            title: "Choose the source task you want to start.",
            description: "Source Management now opens with separate paths for adding feeds, creating folders, and organizing existing sources."
        )
    }

    static func buildSections() -> [SourceManagementScreenSectionPresentation] {
        [
            SourceManagementScreenSectionPresentation(
                id: .startNew,
                title: "Start Something New",
                footer: "Adding a feed and creating a folder stay separate, so URL preview and folder creation do not collapse into one mixed form.",
                items: [
                    item(
                        id: .addFeed,
                        title: "Add Feed",
                        subtitle: "Paste a feed URL, preview the source, and choose where it should live before saving.",
                        systemImageName: "dot.radiowaves.left.and.right",
                        badgeTitle: "New Feed"
                    ),
                    item(
                        id: .createFolder,
                        title: "Create Folder",
                        subtitle: "Create a folder first when you want to organize feeds before adding or moving them.",
                        systemImageName: "folder.badge.plus",
                        badgeTitle: "New Folder"
                    )
                ]
            ),
            SourceManagementScreenSectionPresentation(
                id: .organizeExisting,
                title: "Organize Existing Sources",
                footer: "Folder assignment and move actions are presented as their own flow instead of being hidden inside the initial add-source path.",
                items: [
                    item(
                        id: .moveSource,
                        title: "Move Sources",
                        subtitle: "Move existing feeds between folders or return them to the Ungrouped area without repeating the add flow.",
                        systemImageName: "arrow.left.arrow.right.circle",
                        badgeTitle: "Existing Sources"
                    )
                ]
            )
        ]
    }

    static func buildDestination(
        for scenarioID: SourceManagementScenarioID
    ) -> SourceManagementScenarioPlaceholderPresentation {
        switch scenarioID {
        case .addFeed:
            SourceManagementScenarioPlaceholderPresentation(
                id: .addFeed,
                title: "Add Feed",
                summaryTitle: "Feed Setup",
                summaryDescription: "This flow is dedicated to adding a new feed from URL input through preview and confirmation.",
                steps: [
                    "accept and normalize a feed URL before any network request starts",
                    "preview feed metadata so the user can confirm the source before saving",
                    "choose a destination folder or keep the feed ungrouped"
                ]
            )
        case .createFolder:
            SourceManagementScenarioPlaceholderPresentation(
                id: .createFolder,
                title: "Create Folder",
                summaryTitle: "Folder Setup",
                summaryDescription: "This flow is dedicated to creating a reusable folder before any feed is assigned to it.",
                steps: [
                    "collect a folder name with validation and uniqueness checks",
                    "reserve a compatible sort order for the sidebar grouping model",
                    "return the new folder as a destination for later source assignment"
                ]
            )
        case .moveSource:
            SourceManagementScenarioPlaceholderPresentation(
                id: .moveSource,
                title: "Move Sources",
                summaryTitle: "Source Organization",
                summaryDescription: "This flow is dedicated to reorganizing existing feeds after they are already in the library.",
                steps: [
                    "pick an existing feed instead of starting a new add-feed flow",
                    "move the feed into another folder or back to the ungrouped state",
                    "keep organization work separate from feed creation and URL validation"
                ]
            )
        }
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
