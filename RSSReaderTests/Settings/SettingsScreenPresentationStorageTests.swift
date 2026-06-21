import Foundation
import Testing
@testable import RSSReader

@Suite("Settings Screen / Presentation / Storage")
@MainActor
struct SettingsScreenPresentationStorageTests {
    @Test
    func settingsScreenPresentationBuilderEnablesArticleImageCacheResetWhenCacheExists() throws {
        let sections = SettingsScreenPresentationBuilder.buildSections(
            from: SettingsScreenInputBuilder.build(from: AppSettingsSnapshot()),
            hasArticleImageCache: true
        )
        let storageSection = try #require(sections.first(where: { $0.id == .storage }))

        #expect(
            storageSection.items == [
                .button(
                    SettingsButtonItemPresentation(
                        id: .purgeArchivedArticles,
                        title: SettingsLocalization.clearArchivedArticlesTitle,
                        subtitle: SettingsLocalization.clearArchivedArticlesSubtitle,
                        systemImage: "archivebox",
                        role: .destructive,
                        isEnabled: false
                    )
                ),
                .button(
                    SettingsButtonItemPresentation(
                        id: .clearArticleImageCache,
                        title: SettingsLocalization.clearArticleImageCacheTitle,
                        subtitle: SettingsLocalization.clearArticleImageCacheSubtitle,
                        systemImage: "photo.stack",
                        role: .destructive,
                        isEnabled: true
                    )
                ),
                .button(
                    SettingsButtonItemPresentation(
                        id: .clearFeedIconCache,
                        title: SettingsLocalization.clearFeedIconCacheTitle,
                        subtitle: SettingsLocalization.clearFeedIconCacheSubtitle,
                        systemImage: "newspaper",
                        role: .destructive,
                        isEnabled: false
                    )
                )
            ]
        )
    }

    @Test
    func settingsScreenPresentationBuilderEnablesFeedIconCacheResetWhenCacheExists() throws {
        let sections = SettingsScreenPresentationBuilder.buildSections(
            from: SettingsScreenInputBuilder.build(from: AppSettingsSnapshot()),
            hasFeedIconCache: true
        )
        let storageSection = try #require(sections.first(where: { $0.id == .storage }))

        #expect(
            storageSection.items.last == .button(
                SettingsButtonItemPresentation(
                    id: .clearFeedIconCache,
                    title: SettingsLocalization.clearFeedIconCacheTitle,
                    subtitle: SettingsLocalization.clearFeedIconCacheSubtitle,
                    systemImage: "newspaper",
                    role: .destructive,
                    isEnabled: true
                )
            )
        )
    }

    @Test
    func settingsScreenPresentationBuilderEnablesArchivedArticlePurgeWhenArchivedArticlesExist() throws {
        let sections = SettingsScreenPresentationBuilder.buildSections(
            from: SettingsScreenInputBuilder.build(from: AppSettingsSnapshot()),
            hasArchivedArticles: true
        )
        let storageSection = try #require(sections.first(where: { $0.id == .storage }))

        #expect(
            storageSection.items.first == .button(
                SettingsButtonItemPresentation(
                    id: .purgeArchivedArticles,
                    title: SettingsLocalization.clearArchivedArticlesTitle,
                    subtitle: SettingsLocalization.clearArchivedArticlesSubtitle,
                    systemImage: "archivebox",
                    role: .destructive,
                    isEnabled: true
                )
            )
        )
    }
}
