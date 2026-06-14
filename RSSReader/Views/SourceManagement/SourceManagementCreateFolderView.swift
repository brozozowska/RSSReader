import SwiftUI

struct SourceManagementCreateFolderView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    let presentation: SourceManagementCreateFolderPresentation
    let nameBinding: Binding<String>
    let showsCloseControl: Bool
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

            Section {
                TextField(
                    presentation.namePrompt,
                    text: nameBinding,
                    prompt: Text(SourceManagementLocalization.folderNamePlaceholder)
                )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .onSubmit(submit)

                if let validationMessage = presentation.validationMessage {
                    Text(validationMessage)
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            } header: {
                Text(SourceManagementLocalization.folderNamePrompt)
            } footer: {
                Text(SourceManagementLocalization.folderNameFooter)
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
            } else if presentation.existingFolders.isEmpty == false {
                Section {
                    ForEach(presentation.existingFolders) { folder in
                        HStack(alignment: .firstTextBaseline) {
                            Text(folder.name)
                                .font(.body.weight(.semibold))

                            Spacer()

                            Text(SourceManagementLocalization.feedCount(folder.feedCount))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                } header: {
                    Text(SourceManagementLocalization.existingFoldersTitle)
                }
            }

            if let feedback = presentation.feedback {
                Section {
                    SourceManagementFeedbackCard(
                        feedback: .init(createFolderFeedback: feedback)
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
                        accessibilityLabel: SourceManagementLocalization.closeDestinationAccessibilityLabel(presentation.title),
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
