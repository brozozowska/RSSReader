import Foundation

struct SourceManagementMoveSourceState {
    private(set) var feeds: [SourceManagementFeedSummary] = []
    private(set) var folders: [SourceManagementFolderSummary] = []
    private(set) var selectedFeedID: UUID? = nil
    private(set) var selectedPlacement: SourceManagementFolderPlacement = .ungrouped
    private(set) var isSubmitting = false
    fileprivate(set) var feedback: SourceManagementMoveSourceFeedbackPresentation? = nil

    mutating func applyContext(
        feeds: [SourceManagementFeedSummary],
        folders: [SourceManagementFolderSummary],
        selectedFeedID preferredSelectedFeedID: UUID? = nil
    ) {
        self.feeds = feeds.sorted(by: feedSortComparator)
        self.folders = folders.sorted(by: folderSortComparator)

        if let preferredSelectedFeedID,
           self.feeds.contains(where: { $0.id == preferredSelectedFeedID }) {
            selectedFeedID = preferredSelectedFeedID
            selectedPlacement = currentPlacement(for: preferredSelectedFeedID) ?? .ungrouped
        } else if let selectedFeedID,
           self.feeds.contains(where: { $0.id == selectedFeedID }) {
            selectedPlacement = currentPlacement(for: selectedFeedID) ?? .ungrouped
        } else {
            self.selectedFeedID = self.feeds.first?.id
            selectedPlacement = currentPlacement(for: self.selectedFeedID) ?? .ungrouped
        }

        isSubmitting = false
        if feedback?.kind == .failure {
            feedback = nil
        }
    }

    mutating func selectFeed(_ feedID: UUID) {
        guard feeds.contains(where: { $0.id == feedID }) else { return }
        selectedFeedID = feedID
        selectedPlacement = currentPlacement(for: feedID) ?? .ungrouped
        isSubmitting = false
        feedback = nil
    }

    mutating func selectPlacement(_ placement: SourceManagementFolderPlacement) {
        switch placement {
        case .ungrouped:
            selectedPlacement = .ungrouped
        case .folder(let folderID):
            guard folders.contains(where: { $0.id == folderID }) else { return }
            selectedPlacement = .folder(folderID)
        }
        feedback = nil
    }

    mutating func beginSubmission() {
        isSubmitting = true
        feedback = nil
    }

    mutating func applyMovedFeed(_ feed: SourceManagementFeedSummary) {
        guard let index = feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        feeds[index] = feed
        feeds.sort(by: feedSortComparator)
        selectedFeedID = feed.id
        selectedPlacement = currentPlacement(for: feed.id) ?? .ungrouped
        isSubmitting = false
        feedback = SourceManagementMoveSourceFeedbackPresentation(
            kind: .success,
            title: "Source moved",
            detail: "\(feed.title) now lives in \(placementTitle(for: selectedPlacement))."
        )
    }

    mutating func applyFailure(message: String) {
        isSubmitting = false
        feedback = SourceManagementMoveSourceFeedbackPresentation(
            kind: .failure,
            title: "Source could not be moved",
            detail: message
        )
    }

    func derivedPresentation() -> SourceManagementMoveSourcePresentation {
        let canSubmit = selectedFeedID != nil
            && currentPlacement(for: selectedFeedID) != nil
            && currentPlacement(for: selectedFeedID) != selectedPlacement
            && isSubmitting == false

        return SourceManagementMoveSourcePresentation(
            title: "Move Source",
            summaryTitle: "Source Organization",
            summaryDescription: "Choose a saved feed and move it to the folder where it belongs.",
            feeds: feeds.map { feed in
                SourceManagementMoveSourceFeedPresentation(
                    id: feed.id,
                    title: feed.title,
                    subtitle: feed.url,
                    currentPlacementTitle: placementTitle(for: placement(for: feed)),
                    isSelected: feed.id == selectedFeedID
                )
            },
            emptyStateTitle: feeds.isEmpty ? "No existing feeds yet" : nil,
            emptyStateDescription: feeds.isEmpty
                ? "Add a source first, then return here to move it between folders."
                : nil,
            placementTitle: "Target Folder",
            placementDescription: "",
            placementOptions: placementOptions(),
            primaryActionTitle: isSubmitting ? "Moving..." : "Move Source",
            isPrimaryActionEnabled: canSubmit,
            isSubmitting: isSubmitting,
            feedback: feedback
        )
    }

    func moveCommand() -> SourceManagementMoveFeedCommand? {
        guard let selectedFeedID,
              let currentPlacement = currentPlacement(for: selectedFeedID),
              currentPlacement != selectedPlacement else {
            return nil
        }

        return SourceManagementMoveFeedCommand(
            feedID: selectedFeedID,
            folderPlacement: selectedPlacement
        )
    }

    private func placementOptions() -> [SourceManagementFolderPlacementOptionPresentation] {
        guard selectedFeedID != nil else { return [] }

        return [
            SourceManagementFolderPlacementOptionPresentation(
                placement: .ungrouped,
                title: "Ungrouped",
                subtitle: nil,
                trailingValue: feedCountTitle(ungroupedFeedCount()),
                isSelected: selectedPlacement == .ungrouped
            )
        ] + folders.map { folder in
            SourceManagementFolderPlacementOptionPresentation(
                placement: .folder(folder.id),
                title: folder.name,
                subtitle: nil,
                trailingValue: feedCountTitle(folder.feedCount),
                isSelected: selectedPlacement == .folder(folder.id)
            )
        }
    }

    private func ungroupedFeedCount() -> Int {
        feeds.filter { $0.folderID == nil }.count
    }

    private func feedCountTitle(_ count: Int) -> String {
        count == 1 ? "1 feed" : "\(count) feeds"
    }

    func selectedFeed() -> SourceManagementFeedSummary? {
        guard let selectedFeedID else { return nil }
        return feeds.first(where: { $0.id == selectedFeedID })
    }

    private func currentPlacement(for feedID: UUID?) -> SourceManagementFolderPlacement? {
        guard let feedID,
              let feed = feeds.first(where: { $0.id == feedID }) else { return nil }
        return placement(for: feed)
    }

    private func placement(for feed: SourceManagementFeedSummary) -> SourceManagementFolderPlacement {
        if let folderID = feed.folderID {
            return .folder(folderID)
        }
        return .ungrouped
    }

    private func placementTitle(for placement: SourceManagementFolderPlacement) -> String {
        switch placement {
        case .ungrouped:
            return "Ungrouped"
        case .folder(let folderID):
            return folders.first(where: { $0.id == folderID })?.name ?? "Selected Folder"
        }
    }

    private func feedSortComparator(
        lhs: SourceManagementFeedSummary,
        rhs: SourceManagementFeedSummary
    ) -> Bool {
        if lhs.title == rhs.title {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.title < rhs.title
    }

    private func folderSortComparator(
        lhs: SourceManagementFolderSummary,
        rhs: SourceManagementFolderSummary
    ) -> Bool {
        if lhs.sortOrder == rhs.sortOrder {
            if lhs.name == rhs.name {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.name < rhs.name
        }
        return lhs.sortOrder < rhs.sortOrder
    }
}
