import Foundation

/// Modal flags remain independent: the shell decides which presentation is visible.
struct AppPresentationState {
    private(set) var isPresentingSettingsScreen = false
    private(set) var isPresentingFeedManagementScreen = false
    private(set) var feedManagementLaunchContext: FeedManagementScreenLaunchContext = .entry

    mutating func presentSettingsScreen() { isPresentingSettingsScreen = true }
    mutating func dismissSettingsScreen() { isPresentingSettingsScreen = false }

    mutating func presentFeedManagementScreen(launchContext: FeedManagementScreenLaunchContext = .entry) {
        feedManagementLaunchContext = launchContext
        isPresentingFeedManagementScreen = true
    }

    mutating func dismissFeedManagementScreen() {
        isPresentingFeedManagementScreen = false
        feedManagementLaunchContext = .entry
    }
}

struct PendingFeedUnsubscribeConfirmation: Identifiable, Equatable, Sendable {
    let feedID: UUID
    let feedTitle: String

    var id: UUID { feedID }
}

struct PendingFolderDeleteConfirmation: Identifiable, Equatable, Sendable {
    let folderName: String

    var id: String { folderName }
}


/// A single payload makes simultaneous destructive confirmations unrepresentable.
struct AppConfirmationState {
    private enum Pending {
        case feed(PendingFeedUnsubscribeConfirmation)
        case folder(PendingFolderDeleteConfirmation)
    }

    private var pending: Pending?

    var pendingFeedUnsubscribeConfirmation: PendingFeedUnsubscribeConfirmation? {
        guard case .feed(let confirmation) = pending else { return nil }
        return confirmation
    }

    var pendingFolderDeleteConfirmation: PendingFolderDeleteConfirmation? {
        guard case .folder(let confirmation) = pending else { return nil }
        return confirmation
    }

    mutating func presentFeedUnsubscribeConfirmation(feedID: UUID, feedTitle: String) {
        pending = .feed(PendingFeedUnsubscribeConfirmation(feedID: feedID, feedTitle: feedTitle))
    }

    mutating func dismissFeedUnsubscribeConfirmation() {
        guard case .feed = pending else { return }
        pending = nil
    }

    mutating func presentFolderDeleteConfirmation(folderName: String) {
        pending = .folder(PendingFolderDeleteConfirmation(folderName: folderName))
    }

    mutating func dismissFolderDeleteConfirmation() {
        guard case .folder = pending else { return }
        pending = nil
    }
}
