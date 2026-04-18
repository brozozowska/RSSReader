import SwiftUI

struct SettingsScreenActionHandlers {
    let dismiss: () -> Void
    let retryLoad: () -> Void
    let selectItem: (SettingsScreenItemID) -> Void
    let selectPickerOption: (SettingsScreenItemID, String) -> Void
    let toggleItem: (SettingsScreenItemID, Bool) -> Void
    let dismissPicker: () -> Void
}

struct SettingsScreenView: View {
    @Environment(\.appDependencies) private var dependencies
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
                .task {
                    guard controller.isPreviewMode == false else { return }
                    controller.loadSettings(dependencies: dependencies)
                }
                .confirmationDialog(
                    viewState.presentedPicker?.title ?? "",
                    isPresented: presentedPickerBinding,
                    titleVisibility: .visible
                ) {
                    if let picker = viewState.presentedPicker {
                        ForEach(picker.options) { option in
                            Button(optionTitle(option)) {
                                actionHandlers.selectPickerOption(picker.id, option.id)
                            }
                        }
                    }

                    Button("Cancel", role: .cancel) {
                        actionHandlers.dismissPicker()
                    }
                } message: {
                    if let subtitle = viewState.presentedPicker?.subtitle, subtitle.isEmpty == false {
                        Text(subtitle)
                    }
                }
        }
    }

    private var actionHandlers: SettingsScreenActionHandlers {
        SettingsScreenActionHandlers(
            dismiss: dismiss,
            retryLoad: {
                controller.retryLoadingSettings(dependencies: dependencies)
            },
            selectItem: { itemID in
                controller.handleItemSelection(itemID, dependencies: dependencies)
            },
            selectPickerOption: { itemID, optionID in
                controller.handlePickerOptionSelection(
                    itemID: itemID,
                    optionID: optionID,
                    dependencies: dependencies
                )
            },
            toggleItem: { itemID, isOn in
                controller.handleToggleValueChange(
                    itemID: itemID,
                    isOn: isOn,
                    dependencies: dependencies
                )
            },
            dismissPicker: {
                controller.dismissPresentedPicker()
            }
        )
    }

    private var presentedPickerBinding: Binding<Bool> {
        Binding(
            get: { controller.screenState.presentedPicker != nil },
            set: { isPresented in
                guard isPresented == false else { return }
                controller.dismissPresentedPicker()
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
            Button {
                actionHandlers.selectItem(pickerItem.id)
            } label: {
                LabeledContent {
                    Text(pickerItem.selectedValueTitle)
                        .foregroundStyle(.secondary)
                } label: {
                    itemLabel(
                        title: pickerItem.title,
                        subtitle: pickerItem.subtitle
                    )
                }
            }
            .buttonStyle(.plain)
        case .navigationLink(let navigationItem):
            HStack(spacing: 12) {
                itemLabel(
                    title: navigationItem.title,
                    subtitle: navigationItem.subtitle
                )

                Spacer(minLength: 12)

                if let valueTitle = navigationItem.valueTitle {
                    Text(valueTitle)
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
            .opacity(navigationItem.isEnabled ? 1 : 0.6)
            .onTapGesture {
                guard navigationItem.isEnabled else { return }
                actionHandlers.selectItem(navigationItem.id)
            }
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

    private func optionTitle(_ option: SettingsPickerOptionPresentation) -> String {
        option.isSelected ? "\(option.title) (Current)" : option.title
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
