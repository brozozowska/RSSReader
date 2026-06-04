import Foundation

@MainActor
extension SettingsScreenController {
    func updateArticleOpeningMode(
        optionID: String,
        dependencies: AppDependencies
    ) {
        guard let selectedMode = ArticleOpeningMode(rawValue: optionID) else {
            dependencies.logger.error("Skipped article opening mode update because option is invalid: \(optionID)")
            return
        }

        guard screenState.settingsInput.articleOpeningMode != selectedMode else {
            return
        }

        var input = screenState.settingsInput
        input.articleOpeningMode = selectedMode
        screenState.applyDraftInput(input)
    }

    func updateMarkAsReadOnOpen(
        isOn: Bool,
        dependencies: AppDependencies
    ) {
        guard screenState.settingsInput.markAsReadOnOpen != isOn else {
            return
        }

        var input = screenState.settingsInput
        input.markAsReadOnOpen = isOn
        screenState.applyDraftInput(input)
    }

    func updateArticleBodyLinkOpeningPolicy(
        optionID: String,
        dependencies: AppDependencies
    ) {
        guard let selectedPolicy = ArticleBodyLinkOpeningPolicy(rawValue: optionID) else {
            dependencies.logger.error("Skipped article body link opening policy update because option is invalid: \(optionID)")
            return
        }

        guard screenState.settingsInput.articleBodyLinkOpeningPolicy != selectedPolicy else {
            return
        }

        var input = screenState.settingsInput
        input.articleBodyLinkOpeningPolicy = selectedPolicy
        screenState.applyDraftInput(input)
    }

    func updateArticleSourceLinkOpeningPolicy(
        optionID: String,
        dependencies: AppDependencies
    ) {
        guard let selectedPolicy = ArticleSourceLinkOpeningPolicy(rawValue: optionID) else {
            dependencies.logger.error("Skipped article source link opening policy update because option is invalid: \(optionID)")
            return
        }

        guard screenState.settingsInput.articleSourceLinkOpeningPolicy != selectedPolicy else {
            return
        }

        var input = screenState.settingsInput
        input.articleSourceLinkOpeningPolicy = selectedPolicy
        screenState.applyDraftInput(input)
    }

    func updateReaderAdjacentNavigationControlsMode(
        optionID: String,
        dependencies: AppDependencies
    ) {
        guard let selectedMode = ReaderAdjacentNavigationControlsMode(rawValue: optionID) else {
            dependencies.logger.error("Skipped reader adjacent navigation controls mode update because option is invalid: \(optionID)")
            return
        }

        guard screenState.settingsInput.readerAdjacentNavigationControlsMode != selectedMode else {
            return
        }

        var input = screenState.settingsInput
        input.readerAdjacentNavigationControlsMode = selectedMode
        screenState.applyDraftInput(input)
    }
}
