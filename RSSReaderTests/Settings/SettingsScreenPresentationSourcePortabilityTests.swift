import Foundation
import Testing
@testable import RSSReader

@Suite("Settings Screen / Presentation / Source Portability")
@MainActor
struct SettingsScreenPresentationSourcePortabilityTests {
    @Test
    func settingsScreenPresentationBuilderPlacesSourcePortabilityBeforeStorage() throws {
        let sections = SettingsScreenPresentationBuilder.buildSections(
            from: SettingsScreenInputBuilder.build(from: AppSettingsSnapshot())
        )

        #expect(sections.map(\.id).suffix(2) == [.sourcePortability, .storage])

        let section = try #require(sections.first(where: { $0.id == .sourcePortability }))
        #expect(section.title == SettingsLocalization.sourcePortabilitySectionTitle)
        #expect(section.footer == SettingsLocalization.sourcePortabilitySectionFooter)
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
