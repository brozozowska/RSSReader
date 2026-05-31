import Foundation
import Testing
@testable import RSSReader

@Suite("Sync / CloudKit Scope")
@MainActor
struct CloudKitSyncScopeTests {
    @Test
    func cloudKitSyncScopeDeclaresSyncBackedAndLocalOnlyModels() {
        let scope = CloudKitSyncScope.current

        #expect(scope.syncBackedModels == [.feed, .folder, .articleState, .article, .appSettings])
        #expect(scope.localOnlyModels == [.feedFetchLog])
        #expect(scope.syncs(.feed))
        #expect(scope.syncs(.folder))
        #expect(scope.syncs(.articleState))
        #expect(scope.syncs(.article))
        #expect(scope.syncs(.appSettings))
        #expect(scope.storesLocallyOnly(.feedFetchLog))
        #expect(scope.syncsSourceStructure)
        #expect(scope.syncsReadingState)
        #expect(scope.syncsArticlePayload)
        #expect(scope.syncsAppSettings)
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
        ) + " iCloud sync uses the Apple ID signed in on this device. Changing the sync preference applies on the next app launch."

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
