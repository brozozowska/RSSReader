extension SettingsScreenPresentationBuilder {
    static func appearanceSection(from input: SettingsScreenInput) -> SettingsScreenSectionPresentation {
        SettingsScreenSectionPresentation(
            id: .appearance,
            title: SettingsLocalization.appearanceSectionTitle,
            footer: SettingsLocalization.appearanceSectionFooter,
            items: [
                .picker(
                    SettingsPickerItemPresentation(
                        id: .appearance,
                        title: SettingsLocalization.themePickerTitle,
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
