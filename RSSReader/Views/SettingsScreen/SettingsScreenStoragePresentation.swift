extension SettingsScreenPresentationBuilder {
    static func storageSection(
        hasArticleImageCache: Bool,
        hasSourceIconCache: Bool,
        hasArchivedArticles: Bool
    ) -> SettingsScreenSectionPresentation {
        SettingsScreenSectionPresentation(
            id: .storage,
            title: SettingsLocalization.storageSectionTitle,
            footer: nil,
            items: [
                .button(
                    SettingsButtonItemPresentation(
                        id: .purgeArchivedArticles,
                        title: SettingsLocalization.clearArchivedArticlesTitle,
                        subtitle: SettingsLocalization.clearArchivedArticlesSubtitle,
                        systemImage: "archivebox",
                        role: .destructive,
                        isEnabled: hasArchivedArticles
                    )
                ),
                .button(
                    SettingsButtonItemPresentation(
                        id: .clearArticleImageCache,
                        title: SettingsLocalization.clearArticleImageCacheTitle,
                        subtitle: SettingsLocalization.clearArticleImageCacheSubtitle,
                        systemImage: "photo.stack",
                        role: .destructive,
                        isEnabled: hasArticleImageCache
                    )
                ),
                .button(
                    SettingsButtonItemPresentation(
                        id: .clearSourceIconCache,
                        title: SettingsLocalization.clearSourceIconCacheTitle,
                        subtitle: SettingsLocalization.clearSourceIconCacheSubtitle,
                        systemImage: "newspaper",
                        role: .destructive,
                        isEnabled: hasSourceIconCache
                    )
                )
            ]
        )
    }
}
