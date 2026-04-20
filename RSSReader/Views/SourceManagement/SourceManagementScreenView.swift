import SwiftUI

struct SourceManagementScreenActionHandlers {
    let dismiss: () -> Void
    let selectScenario: (SourceManagementScenarioID) -> Void
    let dismissPresentedScenario: () -> Void
}

struct SourceManagementScreenView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    @State private var controller: SourceManagementScreenController
    let dismiss: () -> Void

    init(
        dismiss: @escaping () -> Void,
        previewScreenState: SourceManagementScreenState? = nil
    ) {
        self.dismiss = dismiss
        self._controller = State(
            initialValue: SourceManagementScreenController(previewScreenState: previewScreenState)
        )
    }

    var body: some View {
        let viewState = controller.viewState()

        NavigationStack {
            List {
                Section {
                    summarySection(viewState.summary)
                }

                ForEach(viewState.sections) { section in
                    Section {
                        ForEach(section.items) { item in
                            Button {
                                actionHandlers.selectScenario(item.id)
                            } label: {
                                SourceManagementScreenItemCard(item: item)
                            }
                            .buttonStyle(.plain)
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
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(appThemeVariant.primaryBackground)
            .navigationTitle("Add Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done", action: actionHandlers.dismiss)
                }
            }
            .navigationDestination(item: presentedDestinationBinding) { destination in
                SourceManagementScenarioPlaceholderView(destination: destination)
            }
        }
    }

    private var actionHandlers: SourceManagementScreenActionHandlers {
        SourceManagementScreenActionHandlers(
            dismiss: dismiss,
            selectScenario: { scenarioID in
                controller.handleScenarioSelection(scenarioID)
            },
            dismissPresentedScenario: {
                controller.dismissPresentedScenario()
            }
        )
    }

    private var presentedDestinationBinding: Binding<SourceManagementScreenDestinationPresentation?> {
        Binding(
            get: { controller.screenState.presentedDestination },
            set: { destination in
                if let destination {
                    controller.handleScenarioSelection(destination.id)
                } else {
                    controller.dismissPresentedScenario()
                }
            }
        )
    }

    private func summarySection(_ summary: SourceManagementScreenSummaryPresentation) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(summary.title)
                .font(.headline)

            Text(summary.description)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

private struct SourceManagementScreenItemCard: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    let item: SourceManagementScreenItemPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(appThemeVariant.secondaryBackground)
                    .frame(width: 40, height: 40)

                Image(systemName: item.systemImageName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)

                    Text(item.badgeTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(appThemeVariant.secondaryBackground)
                        .clipShape(Capsule())
                }

                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }
}

private struct SourceManagementScenarioPlaceholderView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    let destination: SourceManagementScreenDestinationPresentation

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(destination.summaryTitle)
                        .font(.headline)

                    Text(destination.summaryDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
            }

            Section("What This Flow Will Cover") {
                ForEach(destination.steps, id: \.self) { step in
                    Text(step)
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(appThemeVariant.primaryBackground)
        .navigationTitle(destination.title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
