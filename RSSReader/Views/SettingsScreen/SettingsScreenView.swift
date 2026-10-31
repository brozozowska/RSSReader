import SwiftUI
import UniformTypeIdentifiers

struct SettingsScreenActionHandlers {
    let dismiss: () -> Void
    let applyChanges: () -> Void
    let retryLoad: () -> Void
    let tapButton: (SettingsScreenItemID) -> Void
    let selectPickerOption: (SettingsScreenItemID, String) -> Void
    let toggleItem: (SettingsScreenItemID, Bool) -> Void
}

struct SettingsScreenView: View {
    @Environment(\.appDependencies) private var dependencies
    @Environment(\.appThemeVariant) private var appThemeVariant
    @Environment(AppState.self) private var appState
    @State private var controller: SettingsScreenController
    @State private var didCommitSettingsChanges = false
    @State private var isArchivedArticlesPurgeConfirmationPresented = false
    @State private var isArticleImageCacheResetConfirmationPresented = false
    @State private var isFeedIconCacheResetConfirmationPresented = false
    @State private var opmlPresentation = SettingsOPMLPresentationBridge()
    let dismiss: () -> Void

    init(
        dismiss: @escaping () -> Void,
        previewScreenState: SettingsScreenState? = nil
    ) {
        self.dismiss = dismiss
        self._controller = State(initialValue: SettingsScreenController(previewScreenState: previewScreenState))
    }

    var body: some View {
        let viewState = controller.viewState()

        NavigationStack {
            content(using: viewState)
                .navigationTitle(SettingsLocalization.screenTitle)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: actionHandlers.dismiss) {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel(SettingsLocalization.closeSettingsAccessibilityLabel)
                        .accessibilityIdentifier("settings.close")
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: actionHandlers.applyChanges) {
                            Image(systemName: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.accentColor)
                        .disabled(viewState.canApplyChanges == false)
                        .accessibilityLabel(SettingsLocalization.applySettingsAccessibilityLabel)
                    }
                }
                .background(appThemeVariant.primaryBackground)
                .task {
                    guard controller.isPreviewMode == false else { return }
                    controller.loadSettings(dependencies: dependencies, appState: appState)
                    controller.refreshArchivedArticlesAvailability(dependencies: dependencies)
                    await controller.refreshArticleImageCacheAvailability(dependencies: dependencies)
                    await controller.refreshFeedIconCacheAvailability(dependencies: dependencies)
                }
                .onDisappear {
                    guard didCommitSettingsChanges == false else { return }
                    controller.discardPreviewedAppearanceChanges(appState: appState)
                }
                .alert(
                    SettingsLocalization.clearArchivedArticlesAlertTitle,
                    isPresented: $isArchivedArticlesPurgeConfirmationPresented
                ) {
                    Button(SettingsLocalization.clearArchivedArticlesAlertAction, role: .destructive) {
                        actionHandlers.tapButton(.purgeArchivedArticles)
                    }
                    Button(SettingsLocalization.cancelAction, role: .cancel) {}
                } message: {
                    Text(SettingsLocalization.clearArchivedArticlesAlertMessage)
                }
                .alert(
                    SettingsLocalization.clearArticleImageCacheAlertTitle,
                    isPresented: $isArticleImageCacheResetConfirmationPresented
                ) {
                    Button(SettingsLocalization.clearCacheAlertAction, role: .destructive) {
                        actionHandlers.tapButton(.clearArticleImageCache)
                    }
                    Button(SettingsLocalization.cancelAction, role: .cancel) {}
                } message: {
                    Text(SettingsLocalization.clearArticleImageCacheAlertMessage)
                }
                .alert(
                    SettingsLocalization.clearFeedIconCacheAlertTitle,
                    isPresented: $isFeedIconCacheResetConfirmationPresented
                ) {
                    Button(SettingsLocalization.clearCacheAlertAction, role: .destructive) {
                        actionHandlers.tapButton(.clearFeedIconCache)
                    }
                    Button(SettingsLocalization.cancelAction, role: .cancel) {}
                } message: {
                    Text(SettingsLocalization.clearFeedIconCacheAlertMessage)
                }
                .modifier(SettingsOPMLPresentationModifier(
                    controller: controller,
                    presentation: opmlPresentation
                ))
        }
    }

    private var actionHandlers: SettingsScreenActionHandlers {
        SettingsScreenActionHandlers(
            dismiss: dismiss,
            applyChanges: {
                let didApplyChanges = controller.applySettingsChanges(
                    dependencies: dependencies,
                    appState: appState
                )
                if didApplyChanges {
                    didCommitSettingsChanges = true
                    dismiss()
                }
            },
            retryLoad: {
                controller.retryLoadingSettings(dependencies: dependencies, appState: appState)
            },
            tapButton: { itemID in
                Task {
                    await controller.handleButtonTap(
                        itemID: itemID,
                        dependencies: dependencies,
                        appState: appState
                    )
                }
            },
            selectPickerOption: { itemID, optionID in
                controller.handlePickerOptionSelection(
                    itemID: itemID,
                    optionID: optionID,
                    dependencies: dependencies,
                    appState: appState
                )
            },
            toggleItem: { itemID, isOn in
                controller.handleToggleValueChange(
                    itemID: itemID,
                    isOn: isOn,
                    dependencies: dependencies
                )
            }
        )
    }

    @ViewBuilder
    private func content(using viewState: SettingsScreenViewState) -> some View {
        if let primaryLoadingState = viewState.primaryLoadingState {
            ScreenLoadingView(title: primaryLoadingState.title)
        } else if let placeholder = viewState.placeholder {
            ScreenPlaceholderView(
                title: placeholder.title,
                systemImage: placeholder.systemImage,
                description: placeholder.description,
                actionTitle: placeholder.actionTitle,
                action: actionHandlers.retryLoad
            )
        } else {
            List {
                ForEach(viewState.sections) { section in
                    Section {
                        ForEach(section.items) { item in
                            itemRow(item)
                        }
                    } header: {
                        Text(section.title)
                    } footer: {
                        if let footer = section.footer {
                            Text(footer)
                        }
                    }
                }
            }
            .accessibilityIdentifier("settings.list")
            .scrollContentBackground(.hidden)
            .background(appThemeVariant.primaryBackground)
        }
    }

    @ViewBuilder
    private func itemRow(_ item: SettingsScreenItemPresentation) -> some View {
        switch item {
        case .toggle(let toggleItem):
            Toggle(isOn: toggleBinding(for: toggleItem)) {
                itemLabel(
                    title: toggleItem.title,
                    subtitle: toggleItem.subtitle
                )
            }
        case .picker(let pickerItem):
            pickerRow(pickerItem)
        case .statusRow(let statusItem):
            LabeledContent {
                Text(statusItem.valueTitle)
                    .foregroundStyle(.secondary)
            } label: {
                itemLabel(
                    title: statusItem.title,
                    subtitle: statusItem.subtitle
                )
            }
        case .button(let buttonItem):
            Button(role: buttonItem.role.buttonRole) {
                handleButtonTap(buttonItem)
            } label: {
                Label {
                    itemLabel(
                        title: buttonItem.title,
                        subtitle: buttonItem.subtitle
                    )
                } icon: {
                    Image(systemName: buttonItem.systemImage)
                }
            }
            .disabled(buttonItem.isEnabled == false)
            .foregroundStyle(buttonItem.foregroundStyle)
        }
    }

    private func handleButtonTap(_ buttonItem: SettingsButtonItemPresentation) {
        switch buttonItem.id {
        case .importOPML:
            opmlPresentation.isImporterPresented = true
        case .exportOPML:
            opmlPresentation.presentExporter(
                document: controller.makeOPMLExportDocument(dependencies: dependencies)
            )
        case .purgeArchivedArticles:
            isArchivedArticlesPurgeConfirmationPresented = true
        case .clearArticleImageCache:
            isArticleImageCacheResetConfirmationPresented = true
        case .clearFeedIconCache:
            isFeedIconCacheResetConfirmationPresented = true
        case .articleOpeningMode,
                .markAsReadOnOpen,
                .showUnreadCountBadge,
                .articleSourceLinkOpeningPolicy,
                .unreadArticleSortOrder,
                .articleRetentionPolicy,
                .askBeforeMarkingAllAsRead,
                .refreshInterval,
                .useICloudSync,
                .iCloudSyncStatus,
                .articleBodyLinkOpeningPolicy,
                .readerAdjacentNavigationControlsMode,
                .appearance:
            actionHandlers.tapButton(buttonItem.id)
        }
    }

    @ViewBuilder
    private func pickerRow(_ pickerItem: SettingsPickerItemPresentation) -> some View {
        ViewThatFits(in: .horizontal) {
            trailingPickerRow(pickerItem)
            secondaryLinePickerRow(pickerItem)
        }
    }

    private func trailingPickerRow(_ pickerItem: SettingsPickerItemPresentation) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(pickerItem.title)
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(.primary)

            Spacer(minLength: 8)

            pickerValueControl(for: pickerItem, lineLimit: 1)
                .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func secondaryLinePickerRow(_ pickerItem: SettingsPickerItemPresentation) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(pickerItem.title)
                .foregroundStyle(.primary)

            pickerValueControl(for: pickerItem, lineLimit: 1)
        }
    }

    private func pickerValueControl(
        for pickerItem: SettingsPickerItemPresentation,
        lineLimit: Int?
    ) -> some View {
        visiblePickerValue(for: pickerItem, lineLimit: lineLimit)
            .overlay {
                pickerMenuHitTarget(for: pickerItem)
            }
            .contentShape(Rectangle())
    }

    private func visiblePickerValue(
        for pickerItem: SettingsPickerItemPresentation,
        lineLimit: Int?
    ) -> some View {
        HStack(spacing: 4) {
            Text(pickerItem.selectedValueTitle)
                .lineLimit(lineLimit)
                .truncationMode(.tail)
                .multilineTextAlignment(.trailing)

            Image(systemName: "chevron.up.chevron.down")
                .imageScale(.small)
        }
        .foregroundStyle(.secondary)
        .accessibilityHidden(true)
    }

    private func pickerMenuHitTarget(for pickerItem: SettingsPickerItemPresentation) -> some View {
        Menu {
            Picker(pickerItem.title, selection: pickerSelectionBinding(for: pickerItem)) {
                ForEach(pickerItem.options) { option in
                    Text(option.title)
                        .tag(Optional(option.id))
                }
            }
            .pickerStyle(.inline)
        } label: {
            Color.clear
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(pickerItem.title))
        .accessibilityValue(Text(pickerItem.selectedValueTitle))
    }

    private func pickerSelectionBinding(for item: SettingsPickerItemPresentation) -> Binding<String?> {
        Binding(
            get: { item.selectedOptionID },
            set: { optionID in
                guard let optionID else { return }
                actionHandlers.selectPickerOption(item.id, optionID)
            }
        )
    }

    private func itemLabel(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .foregroundStyle(.primary)

            if let subtitle, subtitle.isEmpty == false {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func toggleBinding(for item: SettingsToggleItemPresentation) -> Binding<Bool> {
        Binding(
            get: { item.isOn },
            set: { newValue in
                actionHandlers.toggleItem(item.id, newValue)
            }
        )
    }
}

private extension SettingsButtonItemPresentation {
    var foregroundStyle: Color {
        guard isEnabled else { return .secondary }

        switch role {
        case .normal:
            return .primary
        case .destructive:
            return .red
        }
    }
}

private extension SettingsButtonItemRole {
    var buttonRole: ButtonRole? {
        switch self {
        case .normal:
            nil
        case .destructive:
            .destructive
        }
    }
}
