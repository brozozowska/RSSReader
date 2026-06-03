import Foundation

@MainActor
extension SettingsScreenController {
    func updateInterfaceThemeMode(
        optionID: String,
        dependencies: AppDependencies,
        appState: AppState?
    ) {
        guard let selectedMode = InterfaceThemeMode(rawValue: optionID) else {
            dependencies.logger.error("Skipped interface theme mode update because option is invalid: \(optionID)")
            return
        }

        guard screenState.settingsInput.interfaceThemeMode != selectedMode else {
            return
        }

        var input = screenState.settingsInput
        input.interfaceThemeMode = selectedMode
        screenState.applyDraftInput(input)
    }
}
