import SwiftUI

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
    @State private var isArticleImageCacheResetConfirmationPresented = false
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
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(action: actionHandlers.dismiss) {
                            Image(systemName: "xmark")
                        }
                        .accessibilityLabel("Close Settings")
                    }

                    ToolbarItem(placement: .confirmationAction) {
                        Button(action: actionHandlers.applyChanges) {
                            Image(systemName: "checkmark")
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.accentColor)
                        .disabled(viewState.canApplyChanges == false)
                        .accessibilityLabel("Apply Settings")
                    }
                }
                .background(appThemeVariant.primaryBackground)
                .task {
                    guard controller.isPreviewMode == false else { return }
                    controller.loadSettings(dependencies: dependencies, appState: appState)
                    await controller.refreshArticleImageCacheAvailability(dependencies: dependencies)
                }
                .alert(
                    "Clear article image cache?",
                    isPresented: $isArticleImageCacheResetConfirmationPresented
                ) {
                    Button("Clear Cache", role: .destructive) {
                        actionHandlers.tapButton(.clearArticleImageCache)
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This removes article images saved on this device. Images can be downloaded again when articles are opened.")
                }
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
                        dependencies: dependencies
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
        case .clearArticleImageCache:
            isArticleImageCacheResetConfirmationPresented = true
        case .defaultReaderMode,
                .markAsReadOnOpen,
                .articleSourceLinkOpeningPolicy,
                .articleSortMode,
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
    }

    private func pickerMenuHitTarget(for pickerItem: SettingsPickerItemPresentation) -> some View {
        Menu {
            ForEach(pickerItem.options) { option in
                Button {
                    actionHandlers.selectPickerOption(pickerItem.id, option.id)
                } label: {
                    if option.isSelected {
                        Label(option.title, systemImage: "checkmark")
                    } else {
                        Text(option.title)
                    }
                }
            }
        } label: {
            Color.clear
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(pickerItem.title))
        .accessibilityValue(Text(pickerItem.selectedValueTitle))
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
            return .accentColor
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
