import SwiftUI

struct FeedManagementScreenView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    @Environment(\.appDependencies) private var dependencies
    @Environment(AppState.self) private var appState
    @State private var controller: FeedManagementScreenController
    @State private var destinationPath: [FeedManagementScenarioID] = []
    @State private var activeLaunchContext: FeedManagementScreenLaunchContext
    let dismiss: () -> Void
    let launchContext: FeedManagementScreenLaunchContext

    init(
        dismiss: @escaping () -> Void,
        launchContext: FeedManagementScreenLaunchContext = .entry,
        previewScreenState: FeedManagementScreenState? = nil
    ) {
        self.dismiss = dismiss
        self.launchContext = launchContext
        self._activeLaunchContext = State(initialValue: launchContext)
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
            showsDirectLaunchCloseControl: activeLaunchContext.opensDirectDestination,
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
            .task(id: activeLaunchContext) {
                destinationFactory.handleLaunchContext(activeLaunchContext)
            }
            .onChange(of: launchContext) { _, newValue in
                updateActiveLaunchContext(newValue)
            }
        }
        .presentationDetents(feedManagementPresentationDetents)
    }

    private var feedManagementPresentationDetents: Set<PresentationDetent> {
        switch activeLaunchContext {
        case .editFeed:
            return [.height(260)]
        case .entry, .editFolder, .organizeFeed:
            return [.large]
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

    private func updateActiveLaunchContext(_ newValue: FeedManagementScreenLaunchContext) {
        guard newValue != .entry || activeLaunchContext == .entry else {
            return
        }

        activeLaunchContext = newValue
    }
}
