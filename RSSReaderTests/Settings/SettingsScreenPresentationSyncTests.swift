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
                    title: "Current Status",
                    subtitle: "Sign in to iCloud with the Apple ID used on this device to enable sync.",
                    valueTitle: "Sign In Required"
                )
            )
        )
        #expect(syncSection.footer?.contains("iCloud sync uses the Apple ID signed in on this device.") == true)
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
                    title: "Current Status",
                    subtitle: "This device cannot use iCloud right now because account changes or CloudKit access are restricted.",
                    valueTitle: "Restricted"
                )
            )
        )
        #expect(
            temporarilyUnavailableSection.items.last == .statusRow(
                SettingsStatusRowItemPresentation(
                    id: .iCloudSyncStatus,
                    title: "Current Status",
                    subtitle: "The current iCloud account is temporarily unavailable. Try again later.",
                    valueTitle: "Temporarily Unavailable"
                )
            )
        )
        #expect(
            couldNotDetermineSection.items.last == .statusRow(
                SettingsStatusRowItemPresentation(
                    id: .iCloudSyncStatus,
                    title: "Current Status",
                    subtitle: "The app could not determine the current iCloud account status. Check the device Apple ID and iCloud availability, then try again.",
                    valueTitle: "Account Unavailable"
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
                    title: "Enable iCloud Sync",
                    subtitle: "Saved for the next launch. This session keeps using local data because the current iCloud account is temporarily unavailable.",
                    isOn: true
                )
            )
        )
        #expect(
            syncSection.items.last == .statusRow(
                SettingsStatusRowItemPresentation(
                    id: .iCloudSyncStatus,
                    title: "Current Status",
                    subtitle: "Sync is enabled, but this launch cannot use iCloud because the current account is temporarily unavailable. Relaunch after iCloud becomes available.",
                    valueTitle: "Temporarily Unavailable"
                )
            )
        )
        #expect(
            syncSection.footer?.contains("Sync will try again on the next launch when iCloud is available.") == true
        )
    }
}
