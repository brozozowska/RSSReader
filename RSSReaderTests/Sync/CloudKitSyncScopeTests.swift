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
        #expect(scope.syncsFeedStructure)
        #expect(scope.syncsReadingState)
        #expect(scope.syncsArticlePayload)
        #expect(scope.syncsAppSettings)
        #expect(scope.keepsFeedFetchLogsLocalOnly)
    }

    @Test
    func updatesAndSyncSectionFooterUsesSettingsLevelSyncScopeCopy() throws {
        let sections = SettingsScreenPresentationBuilder.buildSections(
            from: SettingsScreenInputBuilder.build(
                from: AppSettingsSnapshot(useiCloudSync: true),
                iCloudSyncStatus: .statusUnavailable
            )
        )
        let updatesAndSyncSection = try #require(sections.first { $0.id == .updatesAndSync })
        #expect(updatesAndSyncSection.footer == SettingsLocalization.iCloudScopeAccountFooter)
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
