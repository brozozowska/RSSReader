import Foundation
import Testing
@testable import RSSReader

@Suite("Sync / CloudKit Scope")
@MainActor
struct CloudKitSyncScopeTests {
    @Test
    func cloudKitSyncScopeDeclaresSyncBackedAndLocalOnlyModels() {
        let scope = CloudKitSyncScope.current

        #expect(scope.syncBackedModels == [.feed, .folder, .articleState, .appSettings])
        #expect(scope.localOnlyModels == [.article, .feedFetchLog])
        #expect(scope.syncs(.feed))
        #expect(scope.syncs(.folder))
        #expect(scope.syncs(.articleState))
        #expect(scope.syncs(.appSettings))
        #expect(scope.storesLocallyOnly(.article))
        #expect(scope.storesLocallyOnly(.feedFetchLog))
        #expect(scope.syncsSourceStructure)
        #expect(scope.syncsReadingState)
        #expect(scope.syncsAppSettings)
        #expect(scope.keepsArticlesLocalOnly)
        #expect(scope.keepsFeedFetchLogsLocalOnly)
    }

    @Test
    func updatesAndSyncSectionFooterCombinesReadingScenarioAndCloudKitScope() throws {
        let sections = SettingsScreenPresentationBuilder.buildSections(
            from: SettingsScreenInputBuilder.build(
                from: AppSettingsSnapshot(useiCloudSync: true),
                iCloudSyncStatus: .statusUnavailable
            )
        )
        let updatesAndSyncSection = try #require(sections.first { $0.id == .updatesAndSync })
        let expectedFooter = CloudKitSyncScope.current.settingsSectionFooter(
            readingScenario: CrossDeviceReadingScenario.current
        ) + " RSSReader uses the Apple ID already signed in to this device for iCloud sync and does not require a separate app account. Changing the sync preference applies on the next app launch because the model container must be rebuilt for the selected sync policy."

        #expect(updatesAndSyncSection.footer == expectedFooter)
    }

    @Test
    func cloudKitContainerConfigurationDeclaresExplicitPrivateContainerIdentifier() {
        #expect(
            CloudKitContainerConfiguration.containerIdentifier
                == "iCloud.ru.brozozowska.RSSReader"
        )
        #expect(
            CloudKitContainerConfiguration.syncBackedDatabasePolicy
                == .privateContainer("iCloud.ru.brozozowska.RSSReader")
        )
    }
}
