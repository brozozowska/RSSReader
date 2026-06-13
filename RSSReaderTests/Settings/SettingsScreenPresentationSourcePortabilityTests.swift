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
        #expect(section.title == "Source Portability")
        #expect(section.footer == "Import and export OPML files to move feed subscriptions between apps.")
        #expect(section.items == [
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
        ])
    }
}
