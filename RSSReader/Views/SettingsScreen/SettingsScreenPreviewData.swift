import SwiftUI

#Preview("Loading Settings") {
    SettingsScreenPreviewContainer(screenState: .previewLoading())
}

#Preview("Loaded Settings") {
    SettingsScreenPreviewContainer(
        screenState: .previewLoaded(snapshot: SettingsScreenPreviewFactory.loadedSnapshot)
    )
}

#Preview("Failed Settings") {
    SettingsScreenPreviewContainer(
        screenState: .previewFailed(message: "Unable to load settings right now. Try again.")
    )
}

private struct SettingsScreenPreviewContainer: View {
    let dependencies: AppDependencies
    let screenState: SettingsScreenState

    init(screenState: SettingsScreenState) {
        self.dependencies = SettingsScreenPreviewFactory.makeDependencies()
        self.screenState = screenState
    }

    var body: some View {
        SettingsScreenView(
            dismiss: {},
            previewScreenState: screenState
        )
        .environment(\.appDependencies, dependencies)
    }
}

private enum SettingsScreenPreviewFactory {
    static let loadedSnapshot = AppSettingsSnapshot(
        defaultReaderMode: .browser,
        selectedSourcesFilterRawValue: SourcesFilter.starred.rawValue,
        refreshIntervalPreference: .hourly,
        useiCloudSync: true,
        markAsReadOnOpen: false,
        sortMode: .publishedAtAscending
    )

    @MainActor
    static func makeDependencies() -> AppDependencies {
        AppDependencies.makeDefault()
    }
}
