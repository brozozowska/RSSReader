import SwiftUI

struct SourceManagementMoveSourceView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    let presentation: SourceManagementMoveSourcePresentation
    let showsCloseControl: Bool
    let selectFeed: (UUID) -> Void
    let selectPlacement: (SourceManagementFolderPlacement) -> Void
    let submit: () -> Void
    let dismiss: () -> Void

    var body: some View {
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

            if let emptyStateTitle = presentation.emptyStateTitle,
               let emptyStateDescription = presentation.emptyStateDescription {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(emptyStateTitle)
                            .font(.body.weight(.semibold))

                        Text(emptyStateDescription)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            } else {
                Section("Select Source") {
                    ForEach(presentation.feeds) { feed in
                        Button {
                            selectFeed(feed.id)
                        } label: {
                            SourceManagementMoveSourceFeedRow(feed: feed)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Section {
                    ForEach(presentation.placementOptions) { option in
                        Button {
                            selectPlacement(option.placement)
                        } label: {
                            SourceManagementFolderPlacementRow(option: option)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(presentation.placementTitle)
                }
            }

            if let feedback = presentation.feedback {
                Section {
                    SourceManagementFeedbackCard(
                        feedback: .init(moveSourceFeedback: feedback)
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
                    SourceManagementCloseButton(
                        accessibilityLabel: "Close \(presentation.title)",
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
}

private struct SourceManagementMoveSourceFeedRow: View {
    let feed: SourceManagementMoveSourceFeedPresentation

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

                Text("Current location: \(feed.currentPlacementTitle)")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
    }
}
