import SwiftUI

struct SettingsScreenActionHandlers {
    let dismiss: () -> Void
    let retryLoad: () -> Void
    let selectPickerOption: (SettingsScreenItemID, String) -> Void
    let toggleItem: (SettingsScreenItemID, Bool) -> Void
}

struct SettingsScreenView: View {
    @Environment(\.appDependencies) private var dependencies
    @Environment(\.appThemeVariant) private var appThemeVariant
    @Environment(AppState.self) private var appState
    @State private var controller: SettingsScreenController
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
                        Button("Done", action: actionHandlers.dismiss)
                    }
                }
                .background(appThemeVariant.primaryBackground)
                .task {
                    guard controller.isPreviewMode == false else { return }
                    controller.loadSettings(dependencies: dependencies, appState: appState)
                }
        }
    }

    private var actionHandlers: SettingsScreenActionHandlers {
        SettingsScreenActionHandlers(
            dismiss: dismiss,
            retryLoad: {
                controller.retryLoadingSettings(dependencies: dependencies, appState: appState)
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
                LabeledContent {
                    HStack(spacing: 4) {
                        Text(pickerItem.selectedValueTitle)
                        Image(systemName: "chevron.up.chevron.down")
                            .imageScale(.small)
                    }
                    .foregroundStyle(.secondary)
                } label: {
                    itemLabel(
                        title: pickerItem.title,
                        subtitle: pickerItem.subtitle
                    )
                }
            }
            .buttonStyle(.plain)
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
        }
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
