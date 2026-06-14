extension SettingsScreenPresentationBuilder {
    static func notificationsSection(from input: SettingsScreenInput) -> SettingsScreenSectionPresentation {
        SettingsScreenSectionPresentation(
            id: .notifications,
            title: SettingsLocalization.notificationsSectionTitle,
            footer: SettingsLocalization.notificationsSectionFooter,
            items: [
                .toggle(
                    SettingsToggleItemPresentation(
                        id: .showUnreadCountBadge,
                        title: SettingsLocalization.appIconBadgeTitle,
                        subtitle: SettingsLocalization.appIconBadgeSubtitle,
                        isOn: input.showUnreadCountBadge
                    )
                )
            ]
        )
    }
}
