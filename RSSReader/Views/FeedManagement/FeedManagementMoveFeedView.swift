import SwiftUI

struct FeedManagementMoveFeedView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    let presentation: FeedManagementMoveFeedPresentation
    let showsCloseControl: Bool
    let selectFeed: (UUID) -> Void
    let selectPlacement: (FeedManagementFolderPlacement) -> Void
    let submit: () -> Void
    let dismiss: () -> Void

    var body: some View {
        let showsEmptyState = presentation.emptyStateTitle != nil
            && presentation.emptyStateDescription != nil

        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(presentation.summaryTitle)
                        .font(.headline)

                    Text(presentation.summaryDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            ForEach(presentation.sectionOrder) { sectionID in
                switch sectionID {
                case .destinationFolder:
                    destinationFolderSection(showsEmptyState: showsEmptyState)
                case .selectedFeed:
                    selectedFeedSection(showsEmptyState: showsEmptyState)
                }
            }

            if let feedback = presentation.feedback {
                Section {
                    FeedManagementFeedbackCard(
                        feedback: .init(moveFeedFeedback: feedback)
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(appThemeVariant.primaryBackground)
        .navigationTitle(presentation.title)
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(showsCloseControl)
        .toolbar {
            if showsCloseControl {
                ToolbarItem(placement: .cancellationAction) {
                    FeedManagementCloseButton(
                        accessibilityLabel: FeedManagementLocalization.closeDestinationAccessibilityLabel(presentation.title),
                        action: dismiss
                    )
                }
            }

            ToolbarItem(placement: .confirmationAction) {
                Button(action: submit) {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .accessibilityLabel(presentation.primaryActionTitle)
                .disabled(presentation.isPrimaryActionEnabled == false)
            }
        }
    }

    private func destinationFolderSection(showsEmptyState: Bool) -> some View {
        Section {
            if showsEmptyState == false {
                ForEach(presentation.placementOptions) { option in
                    Button {
                        selectPlacement(option.placement)
                    } label: {
                        FeedManagementFolderPlacementRow(option: option)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            if showsEmptyState == false {
                Text(presentation.placementTitle)
            }
        }
    }

    private func selectedFeedSection(showsEmptyState: Bool) -> some View {
        Section {
            if let emptyStateTitle = presentation.emptyStateTitle,
               let emptyStateDescription = presentation.emptyStateDescription {
                VStack(alignment: .leading, spacing: 8) {
                    Text(emptyStateTitle)
                        .font(.body.weight(.semibold))

                    Text(emptyStateDescription)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            } else {
                ForEach(presentation.feeds) { feed in
                    Button {
                        selectFeed(feed.id)
                    } label: {
                        FeedManagementMoveFeedFeedRow(feed: feed)
                    }
                    .buttonStyle(.plain)
                }
            }
        } header: {
            if showsEmptyState == false {
                Text(FeedManagementLocalization.selectFeedTitle)
            }
        }
    }
}

private struct FeedManagementMoveFeedFeedRow: View {
    let feed: FeedManagementMoveFeedFeedPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: feed.isSelected ? "largecircle.fill.circle" : "circle")
                .foregroundStyle(feed.isSelected ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(feed.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(feed.subtitle)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(FeedManagementLocalization.currentLocation(feed.currentPlacementTitle))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
