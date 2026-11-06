import SwiftUI

/// Platform presentation only; file access, preview planning and persistence stay
/// behind SettingsScreenController and the existing FeedPortability services.
struct SettingsOPMLPresentationModifier: ViewModifier {
    @Environment(\.appDependencies) private var dependencies
    @Environment(AppState.self) private var appState
    @Environment(\.appThemeVariant) private var appThemeVariant

    let controller: SettingsScreenController
    @Bindable var presentation: SettingsOPMLPresentationBridge

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: $presentation.isImporterPresented,
                allowedContentTypes: SettingsOPMLFileDocument.readableContentTypes
            ) { result in
                presentation.handleImportResult(result, preparePreview: { url in
                    await controller.prepareOPMLImportPreview(fileURL: url, dependencies: dependencies)
                }, reportFailure: { error in
                    controller.applyOPMLImportPresentationFailure(error, dependencies: dependencies)
                })
            }
            .fileExporter(
                isPresented: $presentation.isExporterPresented,
                document: presentation.exportDocument,
                contentType: SettingsOPMLFileDocument.contentType,
                defaultFilename: "RSSReader-Subscriptions.opml"
            ) { result in
                presentation.clearExportDocument()
                controller.applyOPMLExportCompletion(result, dependencies: dependencies)
            }
            .sheet(
                item: Binding(
                    get: { controller.screenState.opmlImportPreview },
                    set: { newValue in
                        if newValue == nil {
                            controller.dismissOPMLImportPreview()
                        }
                    }
                )
            ) { preview in
                opmlImportPreviewSheet(preview)
            }
            .alert(
                statusAlertTitle(for: controller.screenState.opmlTransferStatus),
                isPresented: Binding(
                    get: { controller.screenState.opmlTransferStatus != nil },
                    set: { isPresented in
                        if isPresented == false {
                            controller.dismissOPMLTransferStatus()
                        }
                    }
                )
            ) {
                Button(SettingsLocalization.okAction, role: .cancel) {
                    controller.dismissOPMLTransferStatus()
                }
            } message: {
                if let status = controller.screenState.opmlTransferStatus {
                    Text(status.message)
                }
            }
            .onDisappear { presentation.endPresentation() }
    }

    private func opmlImportPreviewSheet(_ preview: SettingsOPMLImportPreviewPresentation) -> some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(SettingsLocalization.importPreviewHeadline)
                            .font(.headline)

                        Text(SettingsLocalization.importPreviewDescription)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }

                Section {
                    LabeledContent(SettingsLocalization.importPreviewSubscriptionsTitle, value: "\(preview.totalEntryCount)")
                    LabeledContent(SettingsLocalization.importPreviewReadyTitle, value: "\(preview.importableEntryCount)")
                    LabeledContent(SettingsLocalization.importPreviewSkippedTitle, value: "\(preview.skippedEntryCount)")
                    LabeledContent(SettingsLocalization.importPreviewNewFoldersTitle, value: "\(preview.createdFolderCount)")
                } footer: {
                    Text(SettingsLocalization.importPreviewFooter)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(appThemeVariant.primaryBackground)
            .navigationTitle(SettingsLocalization.importPreviewNavigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        controller.dismissOPMLImportPreview()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .accessibilityLabel(SettingsLocalization.importPreviewCloseAccessibilityLabel)
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(SettingsLocalization.importPreviewImportAction) {
                        controller.commitOPMLImportPreview(
                            dependencies: dependencies,
                            appState: appState
                        )
                    }
                    .disabled(preview.importableEntryCount == 0)
                }
            }
        }
    }

    private func statusAlertTitle(for status: SettingsOPMLTransferStatusPresentation?) -> String {
        status?.title ?? SettingsLocalization.opmlStatusFallbackTitle
    }
}
