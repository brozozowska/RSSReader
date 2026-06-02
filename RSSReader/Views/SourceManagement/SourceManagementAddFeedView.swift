import SwiftUI

struct SourceManagementAddFeedView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    let presentation: SourceManagementAddFeedPresentation
    let urlBinding: Binding<String>
    let displayNameBinding: Binding<String>
    let showsCloseControl: Bool
    let selectPlacement: (SourceManagementFolderPlacement) -> Void
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
                    prompt: Text("example.com")
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
                Text("Feed URL")
            } footer: {
                Text("Use a website address or a direct RSS / Atom feed link.")
            }

            if presentation.showsDisplayNameInput {
                Section {
                    TextField(
                        presentation.displayNamePrompt,
                        text: displayNameBinding,
                        prompt: Text("Source name")
                    )
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .onSubmit(handlePrimaryAction)
                } header: {
                    Text("Display Name")
                } footer: {
                    Text(presentation.displayNameFooter)
                }
            }

            if presentation.isLoadingPreview {
                Section {
                    SourceManagementCheckingSourceView()
                } header: {
                    Text("Source Preview")
                }
            } else if let preview = presentation.preview {
                Section("Source Preview") {
                    SourceManagementAddFeedPreviewCard(preview: preview)
                }
            } else if let status = presentation.status,
                      status.kind == .failure {
                Section {
                    SourceManagementFeedbackCard(
                        feedback: .init(status: status)
                    )
                } header: {
                    Text("Source Preview")
                } footer: {
                    Text("Try a different website address or a direct RSS / Atom feed link.")
                }
            }

            if presentation.placementOptions.isEmpty == false {
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
                } footer: {
                    Text(presentation.placementDescription)
                }
            }

            if let createFolderActionTitle = presentation.createFolderActionTitle {
                Section {
                    Button(createFolderActionTitle, action: startCreateFolder)
                } footer: {
                    Text("Create a folder now if this source should live in a new group.")
                }
            }

            if let status = presentation.status,
               status.kind != .failure || presentation.preview != nil {
                Section {
                    SourceManagementFeedbackCard(
                        feedback: .init(status: status)
                    )
                }
            }

            if presentation.isLoadingPreview == false,
               presentation.preview == nil,
               presentation.status?.kind != .failure {
                Section {
                    Button(action: handlePreviewAction) {
                        Text("Preview Feed")
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
                    SourceManagementCloseButton(
                        accessibilityLabel: "Close \(presentation.title)",
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

private struct SourceManagementCheckingSourceView: View {
    var body: some View {
        HStack {
            Spacer()
            HStack(spacing: 8) {
                AppRefreshIndicator(
                    state: .refreshing,
                    size: 18,
                    lineWidth: 2,
                    tint: AnyShapeStyle(.secondary),
                    accessibilityLabel: "Checking source"
                )

                Text("Checking Source...")
            }
            .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.vertical, 4)
    }
}
private struct SourceManagementAddFeedPreviewCard: View {
    let preview: SourceManagementAddFeedPreviewPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(preview.title)
                .font(.body.weight(.semibold))

            LabeledContent("Feed Type", value: preview.kindTitle)

            if let subtitle = preview.subtitle {
                LabeledContent("Description", value: subtitle)
            }

            LabeledContent("Feed Address", value: preview.resolvedFeedURL)

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
