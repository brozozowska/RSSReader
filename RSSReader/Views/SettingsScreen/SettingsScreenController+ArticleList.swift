import Foundation

@MainActor
extension SettingsScreenController {
    func updateAskBeforeMarkingAllAsRead(
        isOn: Bool,
        dependencies: AppDependencies
    ) {
        guard screenState.settingsInput.askBeforeMarkingAllAsRead != isOn else {
            return
        }

        var input = screenState.settingsInput
        input.askBeforeMarkingAllAsRead = isOn
        screenState.applyDraftInput(input)
    }

    func updateUnreadArticleSortOrder(
        optionID: String,
        dependencies: AppDependencies
    ) {
        guard let selectedOrder = UnreadArticleSortOrder(rawValue: optionID) else {
            dependencies.logger.error("Skipped unread article sort mode update because option is invalid: \(optionID)")
            return
        }

        guard screenState.settingsInput.unreadArticleSortOrder != selectedOrder else {
            return
        }

        var input = screenState.settingsInput
        input.unreadArticleSortOrder = selectedOrder
        screenState.applyDraftInput(input)
    }

    func updateArticleRetentionPolicy(
        optionID: String,
        dependencies: AppDependencies
    ) {
        guard let selectedPolicy = ArticleRetentionPolicy(rawValue: optionID) else {
            dependencies.logger.error("Skipped article retention policy update because option is invalid: \(optionID)")
            return
        }

        guard screenState.settingsInput.articleRetentionPolicy != selectedPolicy else {
            return
        }

        var input = screenState.settingsInput
        input.articleRetentionPolicy = selectedPolicy
        screenState.applyDraftInput(input)
    }
}
