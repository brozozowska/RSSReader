import Foundation

@MainActor
extension SettingsScreenController {
    func updateShowUnreadCountBadge(
        isOn: Bool,
        dependencies: AppDependencies
    ) {
        guard screenState.settingsInput.showUnreadCountBadge != isOn else {
            return
        }

        var input = screenState.settingsInput
        input.showUnreadCountBadge = isOn
        screenState.applyDraftInput(input)
    }
}
