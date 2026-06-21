import Foundation

struct FeedManagementMoveFeedState {
    private(set) var feeds: [FeedManagementFeedSummary] = []
    private(set) var folders: [FeedManagementFolderSummary] = []
    private(set) var selectedFeedID: UUID? = nil
    private(set) var selectedPlacement: FeedManagementFolderPlacement = .ungrouped
    private(set) var isSubmitting = false
    fileprivate(set) var feedback: FeedManagementMoveFeedFeedbackPresentation? = nil

    mutating func applyContext(
        feeds: [FeedManagementFeedSummary],
        folders: [FeedManagementFolderSummary],
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

    mutating func selectPlacement(_ placement: FeedManagementFolderPlacement) {
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

    mutating func applyMovedFeed(_ feed: FeedManagementFeedSummary) {
        guard let index = feeds.firstIndex(where: { $0.id == feed.id }) else { return }
        feeds[index] = feed
        feeds.sort(by: feedSortComparator)
        selectedFeedID = feed.id
        selectedPlacement = currentPlacement(for: feed.id) ?? .ungrouped
        isSubmitting = false
        feedback = FeedManagementMoveFeedFeedbackPresentation(
            kind: .success,
            title: FeedManagementLocalization.feedMovedTitle,
            detail: FeedManagementLocalization.feedMovedDetail(
                feedTitle: feed.title,
                folderTitle: placementTitle(for: selectedPlacement)
            )
        )
    }

    mutating func applyFailure(message: String) {
        isSubmitting = false
        feedback = FeedManagementMoveFeedFeedbackPresentation(
            kind: .failure,
            title: FeedManagementLocalization.feedMoveFailedTitle,
            detail: message
        )
    }

    func derivedPresentation() -> FeedManagementMoveFeedPresentation {
        let canSubmit = selectedFeedID != nil
            && currentPlacement(for: selectedFeedID) != nil
            && currentPlacement(for: selectedFeedID) != selectedPlacement
            && isSubmitting == false

        return FeedManagementMoveFeedPresentation(
            title: FeedManagementLocalization.moveFeedTitle,
            summaryTitle: FeedManagementLocalization.feedOrganizationTitle,
            summaryDescription: FeedManagementLocalization.feedOrganizationDescription,
            feeds: feeds.map { feed in
                FeedManagementMoveFeedFeedPresentation(
                    id: feed.id,
                    title: feed.title,
                    subtitle: feed.url,
                    currentPlacementTitle: placementTitle(for: placement(for: feed)),
                    isSelected: feed.id == selectedFeedID
                )
            },
            emptyStateTitle: feeds.isEmpty ? FeedManagementLocalization.noFeedsTitle : nil,
            emptyStateDescription: feeds.isEmpty
                ? FeedManagementLocalization.noFeedsDescription
                : nil,
            placementTitle: FeedManagementLocalization.targetFolderTitle,
            placementDescription: "",
            placementOptions: placementOptions(),
            primaryActionTitle: isSubmitting
                ? FeedManagementLocalization.movingFeedAction
                : FeedManagementLocalization.moveFeedTitle,
            isPrimaryActionEnabled: canSubmit,
            isSubmitting: isSubmitting,
            feedback: feedback
        )
    }

    func moveCommand() -> FeedManagementMoveFeedCommand? {
        guard let selectedFeedID,
              let currentPlacement = currentPlacement(for: selectedFeedID),
              currentPlacement != selectedPlacement else {
            return nil
        }

        return FeedManagementMoveFeedCommand(
            feedID: selectedFeedID,
            folderPlacement: selectedPlacement
        )
    }

    private func placementOptions() -> [FeedManagementFolderPlacementOptionPresentation] {
        guard selectedFeedID != nil else { return [] }

        return [
            FeedManagementFolderPlacementOptionPresentation(
                placement: .ungrouped,
                title: FeedManagementLocalization.ungroupedTitle,
                subtitle: nil,
                trailingValue: FeedManagementLocalization.feedCount(ungroupedFeedCount()),
                isSelected: selectedPlacement == .ungrouped
            )
        ] + folders.map { folder in
            FeedManagementFolderPlacementOptionPresentation(
                placement: .folder(folder.id),
                title: folder.name,
                subtitle: nil,
                trailingValue: FeedManagementLocalization.feedCount(folder.feedCount),
                isSelected: selectedPlacement == .folder(folder.id)
            )
        }
    }

    private func ungroupedFeedCount() -> Int {
        feeds.filter { $0.folderID == nil }.count
    }

    func selectedFeed() -> FeedManagementFeedSummary? {
        guard let selectedFeedID else { return nil }
        return feeds.first(where: { $0.id == selectedFeedID })
    }

    private func currentPlacement(for feedID: UUID?) -> FeedManagementFolderPlacement? {
        guard let feedID,
              let feed = feeds.first(where: { $0.id == feedID }) else { return nil }
        return placement(for: feed)
    }

    private func placement(for feed: FeedManagementFeedSummary) -> FeedManagementFolderPlacement {
        if let folderID = feed.folderID {
            return .folder(folderID)
        }
        return .ungrouped
    }

    private func placementTitle(for placement: FeedManagementFolderPlacement) -> String {
        switch placement {
        case .ungrouped:
            return FeedManagementLocalization.ungroupedTitle
        case .folder(let folderID):
            return folders.first(where: { $0.id == folderID })?.name
                ?? FeedManagementLocalization.selectedFolderTitle
        }
    }

    private func feedSortComparator(
        lhs: FeedManagementFeedSummary,
        rhs: FeedManagementFeedSummary
    ) -> Bool {
        if lhs.title == rhs.title {
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return lhs.title < rhs.title
    }

    private func folderSortComparator(
        lhs: FeedManagementFolderSummary,
        rhs: FeedManagementFolderSummary
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
