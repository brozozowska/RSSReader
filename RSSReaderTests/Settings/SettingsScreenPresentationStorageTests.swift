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
                        title: "Clear Archived Articles",
                        subtitle: "Remove archived articles except starred ones from this device and iCloud.",
                        systemImage: "archivebox",
                        role: .destructive,
                        isEnabled: false
                    )
                ),
                .button(
                    SettingsButtonItemPresentation(
                        id: .clearArticleImageCache,
                        title: "Clear Article Image Cache",
                        subtitle: "Remove article images saved on this device.",
                        systemImage: "photo.stack",
                        role: .destructive,
                        isEnabled: true
                    )
                ),
                .button(
                    SettingsButtonItemPresentation(
                        id: .clearSourceIconCache,
                        title: "Clear Source Icon Cache",
                        subtitle: "Remove feed icons saved on this device.",
                        systemImage: "newspaper",
                        role: .destructive,
                        isEnabled: false
                    )
                )
            ]
        )
    }

    @Test
    func settingsScreenPresentationBuilderEnablesSourceIconCacheResetWhenCacheExists() throws {
        let sections = SettingsScreenPresentationBuilder.buildSections(
            from: SettingsScreenInputBuilder.build(from: AppSettingsSnapshot()),
            hasSourceIconCache: true
        )
        let storageSection = try #require(sections.first(where: { $0.id == .storage }))

        #expect(
            storageSection.items.last == .button(
                SettingsButtonItemPresentation(
                    id: .clearSourceIconCache,
                    title: "Clear Source Icon Cache",
                    subtitle: "Remove feed icons saved on this device.",
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
                    title: "Clear Archived Articles",
                    subtitle: "Remove archived articles except starred ones from this device and iCloud.",
                    systemImage: "archivebox",
                    role: .destructive,
                    isEnabled: true
                )
            )
        )
    }
}
