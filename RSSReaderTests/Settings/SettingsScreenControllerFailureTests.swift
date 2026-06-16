import BackgroundTasks
import Foundation
import Testing
@testable import RSSReader

@Suite("Settings Screen / Controller / Failure")
@MainActor
struct SettingsScreenControllerFailureTests {
    @Test
    func settingsScreenControllerBuildsFailureStateWhenSettingsServiceIsUnavailable() {
        let controller = SettingsScreenController()
        let dependencies = AppDependencies.makeDefault()

        controller.loadSettings(dependencies: dependencies)

        #expect(controller.viewState().sections.isEmpty)
        #expect(
            controller.viewState().placeholder == SettingsScreenPlaceholderState(
                title: SettingsLocalization.loadFailureTitle,
                systemImage: "exclamationmark.triangle",
                description: SettingsLocalization.unavailableMessage,
                actionTitle: SettingsLocalization.retryActionTitle
            )
        )
    }

    @Test
    func settingsScreenControllerShowsModelContainerBootstrapFailureWhenAvailable() {
        let controller = SettingsScreenController()
        let dependencies = AppDependencies(
            logger: TestLogger(),
            modelContainerBootstrapFailureDescription: "The app could not initialize its data store for the current sync configuration."
        )

        controller.loadSettings(dependencies: dependencies)

        #expect(controller.viewState().sections.isEmpty)
        #expect(
            controller.viewState().placeholder == SettingsScreenPlaceholderState(
                title: SettingsLocalization.loadFailureTitle,
                systemImage: "exclamationmark.triangle",
                description: "The app could not initialize its data store for the current sync configuration.",
                actionTitle: SettingsLocalization.retryActionTitle
            )
        )
    }
}
