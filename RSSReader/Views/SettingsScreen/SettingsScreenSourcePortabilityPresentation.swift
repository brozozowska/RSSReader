extension SettingsScreenPresentationBuilder {
    static func sourcePortabilitySection() -> SettingsScreenSectionPresentation {
        SettingsScreenSectionPresentation(
            id: .sourcePortability,
            title: "Source Portability",
            footer: "Import and export OPML files to move feed subscriptions between apps.",
            items: [
                .button(
                    SettingsButtonItemPresentation(
                        id: .importOPML,
                        title: "Import OPML",
                        subtitle: "Preview subscriptions before adding them.",
                        systemImage: "square.and.arrow.down",
                        role: .normal,
                        isEnabled: true
                    )
                ),
                .button(
                    SettingsButtonItemPresentation(
                        id: .exportOPML,
                        title: "Export OPML",
                        subtitle: "Save active subscriptions as an OPML file.",
                        systemImage: "square.and.arrow.up",
                        role: .normal,
                        isEnabled: true
                    )
                )
            ]
        )
    }
}
