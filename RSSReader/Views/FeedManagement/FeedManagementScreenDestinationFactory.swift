import SwiftUI

struct FeedManagementScreenDestinationFactory {
    let controller: FeedManagementScreenController
    let dependencies: AppDependencies
    let appState: AppState
    let dismiss: () -> Void
    let showsDirectLaunchCloseControl: Bool
    @Binding var destinationPath: [FeedManagementScenarioID]

    func handleLaunchContext(_ launchContext: FeedManagementScreenLaunchContext) {
        controller.handleLaunchContext(launchContext, dependencies: dependencies)
        switch launchContext {
        case .entry:
            return
        case .editFeed:
            destinationPath = [.addFeed]
        case .editFolder:
            destinationPath = [.createFolder]
        case .organizeFeed:
            destinationPath = [.moveFeed]
        }
    }

    func selectScenario(_ scenarioID: FeedManagementScenarioID) {
        controller.handleScenarioSelection(
            scenarioID,
            dependencies: dependencies
        )
        destinationPath = [scenarioID]
    }

    func startCreateFolderFromAddFeed() {
        controller.startCreateFolderFromAddFeed(dependencies: dependencies)
        destinationPath.append(.createFolder)
    }

    func submitCreateFolder() {
        let wasNestedAddFeedFolderCreation = destinationPath == [.addFeed, .createFolder]
        controller.submitCreateFolder(
            dependencies: dependencies,
            appState: appState
        )

        if wasNestedAddFeedFolderCreation,
           controller.screenState.presentedDestination?.id == .addFeed {
            destinationPath = [.addFeed]
        }
    }

    @ViewBuilder
    func destinationView(
        for scenarioID: FeedManagementScenarioID
    ) -> some View {
        let destination = controller.screenState.destinationPresentation(for: scenarioID)

        switch destination {
        case .addFeed(let addFeed):
            FeedManagementAddFeedView(
                presentation: addFeed,
                urlBinding: addFeedURLBinding,
                displayNameBinding: addFeedDisplayNameBinding,
                showsCloseControl: showsDirectLaunchCloseControl,
                selectPlacement: { placement in
                    controller.handleAddFeedFolderPlacementSelection(placement)
                },
                startCreateFolder: {
                    startCreateFolderFromAddFeed()
                },
                handlePrimaryAction: {
                    Task {
                        await controller.handleAddFeedPrimaryAction(
                            dependencies: dependencies,
                            appState: appState
                        )
                    }
                },
                handlePreviewAction: {
                    Task {
                        await controller.handleAddFeedPreviewAction(
                            dependencies: dependencies
                        )
                    }
                },
                dismiss: dismiss
            )
        case .createFolder(let createFolder):
            FeedManagementCreateFolderView(
                presentation: createFolder,
                nameBinding: createFolderNameBinding,
                showsCloseControl: showsDirectLaunchCloseControl,
                submit: {
                    submitCreateFolder()
                },
                dismiss: dismiss
            )
        case .moveFeed(let moveFeed):
            FeedManagementMoveFeedView(
                presentation: moveFeed,
                showsCloseControl: showsDirectLaunchCloseControl,
                selectFeed: { feedID in
                    controller.handleMoveFeedFeedSelection(feedID)
                },
                selectPlacement: { placement in
                    controller.handleMoveFeedPlacementSelection(placement)
                },
                submit: {
                    controller.submitMoveFeed(
                        dependencies: dependencies,
                        appState: appState
                    )
                },
                dismiss: dismiss
            )
        }
    }

    private var addFeedURLBinding: Binding<String> {
        Binding(
            get: { controller.screenState.addFeedURLInput() },
            set: { value in
                controller.handleAddFeedURLChange(value)
            }
        )
    }

    private var addFeedDisplayNameBinding: Binding<String> {
        Binding(
            get: { controller.screenState.addFeedDisplayNameInput() },
            set: { value in
                controller.handleAddFeedDisplayNameChange(value)
            }
        )
    }

    private var createFolderNameBinding: Binding<String> {
        Binding(
            get: { controller.screenState.createFolderNameInput() },
            set: { value in
                controller.handleCreateFolderNameChange(value)
            }
        )
    }
}
