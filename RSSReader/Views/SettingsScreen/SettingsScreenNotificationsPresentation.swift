extension SettingsScreenPresentationBuilder {
    static func notificationsSection(from input: SettingsScreenInput) -> SettingsScreenSectionPresentation {
        SettingsScreenSectionPresentation(
            id: .notifications,
            title: "Notifications",
            footer: "App does not send notifications. iOS still requires notification permission to show a badge on the app icon.",
            items: [
                .toggle(
                    SettingsToggleItemPresentation(
                        id: .showUnreadCountBadge,
                        title: "App Icon Badge",
                        subtitle: "Show the unread article count on the app icon.",
                        isOn: input.showUnreadCountBadge
                    )
                )
            ]
        )
    }
}
