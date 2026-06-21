import Foundation
import Testing
@testable import RSSReader

@Suite("Settings Screen / Presentation / Sync")
@MainActor
struct SettingsScreenPresentationSyncTests {
    @Test
    func settingsScreenPresentationBuilderShowsAppleIDSignInGuidanceWhenNoICloudAccountIsAvailable() throws {
        let input = SettingsScreenInput(
            useiCloudSync: true,
            iCloudSyncStatus: .statusUnavailable,
            syncStatusPresentation: .noAccount
        )

        let syncSection = try #require(
            SettingsScreenPresentationBuilder.buildSections(from: input).first(where: { $0.id == .updatesAndSync })
        )
        let statusRow = try #require(syncSection.items.last)

        #expect(
            statusRow == .statusRow(
                SettingsStatusRowItemPresentation(
                    id: .iCloudSyncStatus,
                    title: SettingsLocalization.currentStatusTitle,
                    subtitle: SettingsLocalization.syncNoAccountSubtitle,
                    valueTitle: SettingsLocalization.syncStatusNoAccountTitle
                )
            )
        )
        #expect(syncSection.footer?.contains(SettingsLocalization.iCloudScopeAccountFooter) == true)
    }

    @Test
    func settingsScreenPresentationBuilderShowsSpecificAccountProblemCopyForRestrictedAndTemporaryCases() throws {
        let restrictedInput = SettingsScreenInput(
            useiCloudSync: true,
            iCloudSyncStatus: .statusUnavailable,
            syncStatusPresentation: .restricted
        )
        let temporarilyUnavailableInput = SettingsScreenInput(
            useiCloudSync: true,
            iCloudSyncStatus: .statusUnavailable,
            syncStatusPresentation: .temporarilyUnavailable
        )
        let couldNotDetermineInput = SettingsScreenInput(
            useiCloudSync: true,
            iCloudSyncStatus: .statusUnavailable,
            syncStatusPresentation: .couldNotDetermine
        )

        let restrictedSection = try #require(
            SettingsScreenPresentationBuilder.buildSections(from: restrictedInput).first(where: { $0.id == .updatesAndSync })
        )
        let temporarilyUnavailableSection = try #require(
            SettingsScreenPresentationBuilder.buildSections(from: temporarilyUnavailableInput).first(where: { $0.id == .updatesAndSync })
        )
        let couldNotDetermineSection = try #require(
            SettingsScreenPresentationBuilder.buildSections(from: couldNotDetermineInput).first(where: { $0.id == .updatesAndSync })
        )

        #expect(
            restrictedSection.items.last == .statusRow(
                SettingsStatusRowItemPresentation(
                    id: .iCloudSyncStatus,
                    title: SettingsLocalization.currentStatusTitle,
                    subtitle: SettingsLocalization.syncRestrictedSubtitle,
                    valueTitle: SettingsLocalization.syncStatusRestrictedTitle
                )
            )
        )
        #expect(
            temporarilyUnavailableSection.items.last == .statusRow(
                SettingsStatusRowItemPresentation(
                    id: .iCloudSyncStatus,
                    title: SettingsLocalization.currentStatusTitle,
                    subtitle: SettingsLocalization.syncTemporarilyUnavailableSubtitle,
                    valueTitle: SettingsLocalization.syncStatusTemporarilyUnavailableTitle
                )
            )
        )
        #expect(
            couldNotDetermineSection.items.last == .statusRow(
                SettingsStatusRowItemPresentation(
                    id: .iCloudSyncStatus,
                    title: SettingsLocalization.currentStatusTitle,
                    subtitle: SettingsLocalization.syncCouldNotDetermineSubtitle,
                    valueTitle: SettingsLocalization.syncStatusCouldNotDetermineTitle
                )
            )
        )
    }

    @Test
    func settingsScreenPresentationBuilderExplainsLocalOnlyFallbackWhenSyncPreferenceIsSavedButBootstrapStayedLocal() throws {
        let input = SettingsScreenInput(
            useiCloudSync: true,
            iCloudSyncStatus: .statusUnavailable,
            syncStatusPresentation: .temporarilyUnavailable,
            isUsingLocalOnlySyncFallbackForCurrentLaunch: true
        )

        let syncSection = try #require(
            SettingsScreenPresentationBuilder.buildSections(from: input).first(where: { $0.id == .updatesAndSync })
        )

        #expect(
            syncSection.items.dropFirst().first == .toggle(
                SettingsToggleItemPresentation(
                    id: .useICloudSync,
                    title: SettingsLocalization.enableICloudSyncTitle,
                    subtitle: SettingsLocalization.iCloudSyncPreferenceFallbackSubtitle(
                        reason: SettingsLocalization.bootstrapFallbackTemporarilyUnavailableReason
                    ),
                    isOn: true
                )
            )
        )
        #expect(
            syncSection.items.last == .statusRow(
                SettingsStatusRowItemPresentation(
                    id: .iCloudSyncStatus,
                    title: SettingsLocalization.currentStatusTitle,
                    subtitle: SettingsLocalization.syncFallbackTemporarilyUnavailableSubtitle,
                    valueTitle: SettingsLocalization.syncStatusTemporarilyUnavailableTitle
                )
            )
        )
        #expect(
            syncSection.footer?.contains(SettingsLocalization.iCloudScopeFallbackFooter) == true
        )
    }
}
