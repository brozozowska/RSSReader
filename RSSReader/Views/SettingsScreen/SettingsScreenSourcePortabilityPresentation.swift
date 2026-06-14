extension SettingsScreenPresentationBuilder {
    static func sourcePortabilitySection() -> SettingsScreenSectionPresentation {
        SettingsScreenSectionPresentation(
            id: .sourcePortability,
            title: SettingsLocalization.sourcePortabilitySectionTitle,
            footer: SettingsLocalization.sourcePortabilitySectionFooter,
            items: [
                .button(
                    SettingsButtonItemPresentation(
                        id: .importOPML,
                        title: SettingsLocalization.importOPMLTitle,
                        subtitle: SettingsLocalization.importOPMLSubtitle,
                        systemImage: "square.and.arrow.down",
                        role: .normal,
                        isEnabled: true
                    )
                ),
                .button(
                    SettingsButtonItemPresentation(
                        id: .exportOPML,
                        title: SettingsLocalization.exportOPMLTitle,
                        subtitle: SettingsLocalization.exportOPMLSubtitle,
                        systemImage: "square.and.arrow.up",
                        role: .normal,
                        isEnabled: true
                    )
                )
            ]
        )
    }
}
