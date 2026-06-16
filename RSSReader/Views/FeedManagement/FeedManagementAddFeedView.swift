import SwiftUI

struct FeedManagementAddFeedView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    let presentation: FeedManagementAddFeedPresentation
    let urlBinding: Binding<String>
    let displayNameBinding: Binding<String>
    let showsCloseControl: Bool
    let selectPlacement: (FeedManagementFolderPlacement) -> Void
    let startCreateFolder: () -> Void
    let handlePrimaryAction: () -> Void
    let handlePreviewAction: () -> Void
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

            Section {
                TextField(
                    presentation.urlPrompt,
                    text: urlBinding,
                    prompt: Text(FeedManagementLocalization.feedURLPlaceholder)
                )
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .textContentType(.URL)
                .submitLabel(.done)
                .onSubmit(handlePreviewAction)

                if let validationMessage = presentation.validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text(FeedManagementLocalization.feedURLPrompt)
            } footer: {
                Text(FeedManagementLocalization.feedURLFooter)
            }

            if presentation.showsDisplayNameInput {
                Section {
                    TextField(
                        presentation.displayNamePrompt,
                        text: displayNameBinding,
                        prompt: Text(FeedManagementLocalization.displayNamePlaceholder)
                    )
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(handlePrimaryAction)
                } header: {
                    Text(FeedManagementLocalization.displayNamePrompt)
                } footer: {
                    Text(presentation.displayNameFooter)
                }
            }

            if presentation.isLoadingPreview {
                Section {
                    FeedManagementCheckingFeedView()
                } header: {
                    Text(FeedManagementLocalization.feedPreviewTitle)
                }
            } else if let preview = presentation.preview {
                Section(FeedManagementLocalization.feedPreviewTitle) {
                    FeedManagementAddFeedPreviewCard(preview: preview)
                }
            } else if let status = presentation.status,
                      status.kind == .failure {
                Section {
                    FeedManagementFeedbackCard(
                        feedback: .init(status: status)
                    )
                } header: {
                    Text(FeedManagementLocalization.feedPreviewTitle)
                } footer: {
                    Text(FeedManagementLocalization.previewFailureFooter)
                }
            }

            if presentation.placementOptions.isEmpty == false {
                Section {
                    ForEach(presentation.placementOptions) { option in
                        Button {
                            selectPlacement(option.placement)
                        } label: {
                            FeedManagementFolderPlacementRow(option: option)
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(presentation.placementTitle)
                } footer: {
                    Text(presentation.placementDescription)
                }
            }

            if let createFolderActionTitle = presentation.createFolderActionTitle {
                Section {
                    Button(createFolderActionTitle, action: startCreateFolder)
                } footer: {
                    Text(FeedManagementLocalization.createFolderInlineDescription)
                }
            }

            if let status = presentation.status,
               status.kind != .failure || presentation.preview != nil {
                Section {
                    FeedManagementFeedbackCard(
                        feedback: .init(status: status)
                    )
                }
            }

            if presentation.isLoadingPreview == false,
               presentation.preview == nil,
               presentation.status?.kind != .failure {
                Section {
                    Button(action: handlePreviewAction) {
                        Text(FeedManagementLocalization.previewFeedAction)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.tint)
                    .disabled(presentation.validationMessage != nil)
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
                Button(action: handlePrimaryAction) {
                    Image(systemName: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.accentColor)
                .accessibilityLabel(presentation.primaryActionTitle)
                .disabled(presentation.isConfirmationActionEnabled == false)
            }
        }
    }
}

private struct FeedManagementCheckingFeedView: View {
    var body: some View {
        HStack {
            Spacer()
            HStack(spacing: 8) {
                    AppRefreshIndicator(
                        state: .refreshing,
                        size: 18,
                        lineWidth: 2,
                        tint: AnyShapeStyle(.secondary),
                        accessibilityLabel: FeedManagementLocalization.checkingFeedAccessibilityLabel
                    )

                Text(FeedManagementLocalization.checkingFeedTitle)
            }
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
private struct FeedManagementAddFeedPreviewCard: View {
    let preview: FeedManagementAddFeedPreviewPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preview.title)
                .font(.body.weight(.semibold))

            LabeledContent(FeedManagementLocalization.feedTypeLabel, value: preview.kindTitle)

            if let subtitle = preview.subtitle {
                LabeledContent(FeedManagementLocalization.descriptionLabel, value: subtitle)
            }

            LabeledContent(FeedManagementLocalization.feedAddressLabel, value: preview.resolvedFeedURL)

            if let existingFeedNotice = preview.existingFeedNotice {
                Text(existingFeedNotice)
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            if let diagnosticsSummary = preview.diagnosticsSummary {
                Text(diagnosticsSummary)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
