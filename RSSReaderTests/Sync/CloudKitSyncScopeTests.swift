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
    func syncSectionFooterCombinesReadingScenarioAndCloudKitScope() throws {
        let sections = SettingsScreenPresentationBuilder.buildSections(
            from: SettingsScreenInputBuilder.build(
                from: AppSettingsSnapshot(useiCloudSync: true),
                iCloudSyncStatus: .statusUnavailable
            )
        )
        let syncSection = try #require(sections.first { $0.id == .sync })

        #expect(
            syncSection.footer
                == CloudKitSyncScope.current.settingsSectionFooter(
                    readingScenario: CrossDeviceReadingScenario.current
                )
        )
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
