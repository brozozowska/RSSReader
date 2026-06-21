import Foundation
import Testing
@testable import RSSReader

@Suite("Settings Screen / Presentation / Feed Portability")
@MainActor
struct SettingsScreenPresentationFeedPortabilityTests {
    @Test
    func settingsScreenPresentationBuilderPlacesFeedPortabilityBeforeStorage() throws {
        let sections = SettingsScreenPresentationBuilder.buildSections(
            from: SettingsScreenInputBuilder.build(from: AppSettingsSnapshot())
        )

        #expect(sections.map(\.id).suffix(2) == [.feedPortability, .storage])

        let section = try #require(sections.first(where: { $0.id == .feedPortability }))
        #expect(section.title == SettingsLocalization.feedPortabilitySectionTitle)
        #expect(section.footer == SettingsLocalization.feedPortabilitySectionFooter)
        #expect(section.items == [
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
        ])
    }
}
