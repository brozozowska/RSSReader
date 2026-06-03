extension SettingsScreenPresentationBuilder {
    static func storageSection(
        hasArticleImageCache: Bool,
        hasSourceIconCache: Bool,
        hasArchivedArticles: Bool
    ) -> SettingsScreenSectionPresentation {
        SettingsScreenSectionPresentation(
            id: .storage,
            title: "Storage",
            footer: nil,
            items: [
                .button(
                    SettingsButtonItemPresentation(
                        id: .purgeArchivedArticles,
                        title: "Clear Archived Articles",
                        subtitle: "Remove archived articles except starred ones from this device and iCloud.",
                        systemImage: "archivebox",
                        role: .destructive,
                        isEnabled: hasArchivedArticles
                    )
                ),
                .button(
                    SettingsButtonItemPresentation(
                        id: .clearArticleImageCache,
                        title: "Clear Article Image Cache",
                        subtitle: "Remove article images saved on this device.",
                        systemImage: "photo.stack",
                        role: .destructive,
                        isEnabled: hasArticleImageCache
                    )
                ),
                .button(
                    SettingsButtonItemPresentation(
                        id: .clearSourceIconCache,
                        title: "Clear Source Icon Cache",
                        subtitle: "Remove feed icons saved on this device.",
                        systemImage: "newspaper",
                        role: .destructive,
                        isEnabled: hasSourceIconCache
                    )
                )
            ]
        )
    }
}
