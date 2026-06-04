extension SettingsScreenPresentationBuilder {
    static func appearanceSection(from input: SettingsScreenInput) -> SettingsScreenSectionPresentation {
        SettingsScreenSectionPresentation(
            id: .appearance,
            title: "Appearance",
            footer: "Choose how the app renders its interface. The selected mode applies immediately.",
            items: [
                .picker(
                    SettingsPickerItemPresentation(
                        id: .appearance,
                        title: "Theme",
                        subtitle: nil,
                        selectedValueTitle: SettingsScreenPresentationFormatter.interfaceThemeModeTitle(input.interfaceThemeMode),
                        options: InterfaceThemeMode.allCases.map { mode in
                            SettingsPickerOptionPresentation(
                                id: mode.rawValue,
                                title: SettingsScreenPresentationFormatter.interfaceThemeModeTitle(mode),
                                isSelected: input.interfaceThemeMode == mode
                            )
                        }
                    )
                )
            ]
        )
    }
}
