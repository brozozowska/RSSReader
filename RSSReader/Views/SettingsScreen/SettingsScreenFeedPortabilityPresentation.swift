extension SettingsScreenPresentationBuilder {
    static func feedPortabilitySection() -> SettingsScreenSectionPresentation {
        SettingsScreenSectionPresentation(
            id: .feedPortability,
            title: SettingsLocalization.feedPortabilitySectionTitle,
            footer: SettingsLocalization.feedPortabilitySectionFooter,
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
