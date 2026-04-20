import SwiftUI

#Preview("Source Management Screen") {
    SourceManagementScreenPreviewContainer(
        screenState: .previewLoaded()
    )
}

#Preview("Source Management Screen · Move Sources") {
    SourceManagementScreenPreviewContainer(
        screenState: .previewLoaded(presentedScenarioID: .moveSource)
    )
}

private struct SourceManagementScreenPreviewContainer: View {
    let dependencies: AppDependencies
    let screenState: SourceManagementScreenState

    init(screenState: SourceManagementScreenState) {
        self.dependencies = SourceManagementScreenPreviewFactory.makeDependencies()
        self.screenState = screenState
    }

    var body: some View {
        SourceManagementScreenView(
            dismiss: {},
            previewScreenState: screenState
        )
        .environment(\.appDependencies, dependencies)
    }
}

private enum SourceManagementScreenPreviewFactory {
    @MainActor
    static func makeDependencies() -> AppDependencies {
        AppDependencies.makeDefault()
    }
}
