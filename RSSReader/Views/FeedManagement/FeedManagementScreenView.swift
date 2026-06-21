import SwiftUI

struct FeedManagementScreenView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    @Environment(\.appDependencies) private var dependencies
    @Environment(AppState.self) private var appState
    @State private var controller: FeedManagementScreenController
    @State private var destinationPath: [FeedManagementScenarioID] = []
    let dismiss: () -> Void
    let launchContext: FeedManagementScreenLaunchContext

    init(
        dismiss: @escaping () -> Void,
        launchContext: FeedManagementScreenLaunchContext = .entry,
        previewScreenState: FeedManagementScreenState? = nil
    ) {
        self.dismiss = dismiss
        self.launchContext = launchContext
        self._controller = State(
            initialValue: FeedManagementScreenController(previewScreenState: previewScreenState)
        )
    }

    var body: some View {
        let viewState = controller.viewState()
        let destinationFactory = FeedManagementScreenDestinationFactory(
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
                                FeedManagementScreenItemCard(item: item)
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
            .navigationTitle(FeedManagementLocalization.screenTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    FeedManagementCloseButton(
                        accessibilityLabel: FeedManagementLocalization.closeScreenAccessibilityLabel,
                        action: destinationFactory.dismiss
                    )
                }
            }
            .navigationDestination(for: FeedManagementScenarioID.self) { scenarioID in
                destinationFactory.destinationView(for: scenarioID)
            }
            .task(id: launchContext) {
                destinationFactory.handleLaunchContext(launchContext)
            }
        }
    }

    private var destinationPathBinding: Binding<[FeedManagementScenarioID]> {
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

    private func summarySection(_ summary: FeedManagementScreenSummaryPresentation) -> some View {
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
