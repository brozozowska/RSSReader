import SwiftUI

struct SourceManagementScreenView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    @Environment(\.appDependencies) private var dependencies
    @Environment(AppState.self) private var appState
    @State private var controller: SourceManagementScreenController
    @State private var destinationPath: [SourceManagementScenarioID] = []
    let dismiss: () -> Void
    let launchContext: SourceManagementScreenLaunchContext

    init(
        dismiss: @escaping () -> Void,
        launchContext: SourceManagementScreenLaunchContext = .entry,
        previewScreenState: SourceManagementScreenState? = nil
    ) {
        self.dismiss = dismiss
        self.launchContext = launchContext
        self._controller = State(
            initialValue: SourceManagementScreenController(previewScreenState: previewScreenState)
        )
    }

    var body: some View {
        let viewState = controller.viewState()
        let destinationFactory = SourceManagementScreenDestinationFactory(
            controller: controller,
            dependencies: dependencies,
            appState: appState,
            dismiss: dismiss,
            showsDirectLaunchCloseControl: launchContext.opensDirectDestination,
            destinationPath: $destinationPath
        )

        NavigationStack(path: destinationPathBinding) {
            List {
                Section {
                    summarySection(viewState.summary)
                }

                ForEach(viewState.sections) { section in
                    Section {
                        ForEach(section.items) { item in
                            Button {
                                destinationFactory.selectScenario(item.id)
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
            .navigationTitle(SourceManagementLocalization.screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    SourceManagementCloseButton(
                        accessibilityLabel: SourceManagementLocalization.closeScreenAccessibilityLabel,
                        action: destinationFactory.dismiss
                    )
                }
            }
            .navigationDestination(for: SourceManagementScenarioID.self) { scenarioID in
                destinationFactory.destinationView(for: scenarioID)
            }
            .task(id: launchContext) {
                destinationFactory.handleLaunchContext(launchContext)
            }
        }
    }

    private var destinationPathBinding: Binding<[SourceManagementScenarioID]> {
        Binding(
            get: { destinationPath },
            set: { newPath in
                let oldPath = destinationPath
                destinationPath = newPath

                if newPath.count < oldPath.count {
                    controller.dismissPresentedScenario()
                }

                if let activeScenario = newPath.last {
                    controller.screenState.presentScenario(activeScenario)
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
