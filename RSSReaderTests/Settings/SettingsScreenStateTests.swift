import Foundation
import Testing
@testable import RSSReader

@Suite("Settings Screen / State")
@MainActor
struct SettingsScreenStateTests {
    @Test
    func settingsScreenStateBuildsLoadedViewStateFromSnapshot() {
        let snapshot = AppSettingsSnapshot(
            articleOpeningMode: .safariView,
            selectedSourcesFilterRawValue: SidebarArticleFilter.starred.rawValue,
            refreshIntervalPreference: .hourly,
            useiCloudSync: true,
            markAsReadOnOpen: false,
            unreadArticleSortMode: .publishedAtAscending,
            articleRetentionPolicy: .twoDays
        )
        var state = SettingsScreenState()

        state.applyLoadedSnapshot(snapshot)
        let viewState = state.derivedViewState()

        #expect(viewState.primaryLoadingState == nil)
        #expect(viewState.placeholder == nil)
        #expect(viewState.sections.map(\.id) == [
            .appearance,
            .reading,
            .articleList,
            .updatesAndSync,
            .notifications,
            .sourcePortability,
            .storage
        ])
        #expect(state.settingsInput.articleOpeningMode == .safariView)
        #expect(state.settingsInput.unreadArticleSortOrder == .oldestFirst)
        #expect(state.settingsInput.articleRetentionPolicy == .twoDays)
        #expect(state.settingsInput.iCloudSyncStatus == .disabled)
        #expect(state.hasArticleImageCache == false)
        #expect(state.hasSourceIconCache == false)
        #expect(state.hasArchivedArticles == false)
    }

    @Test
    func settingsScreenStateDoesNotTreatLastSourcesRefreshDateAsDraftChange() {
        let snapshot = AppSettingsSnapshot(
            lastSourcesRefreshAt: Date(timeIntervalSinceReferenceDate: 100)
        )
        var state = SettingsScreenState()

        state.applyLoadedSnapshot(snapshot)

        #expect(state.derivedViewState().canApplyChanges == false)

        var input = state.settingsInput
        input.markAsReadOnOpen.toggle()
        state.applyDraftInput(input)

        #expect(state.derivedViewState().canApplyChanges)
    }

    @Test
    func settingsScreenStateKeepsArticleOpeningModePickerInLoadedSections() throws {
        let state = SettingsScreenState.previewLoaded(
            snapshot: AppSettingsSnapshot(articleOpeningMode: .feedReader)
        )

        let readingSection = try #require(
            state.derivedViewState().sections.first(where: { $0.id == .reading })
        )
        let pickerItem = try #require(
            readingSection.items.compactMap { item -> SettingsPickerItemPresentation? in
                guard case .picker(let pickerItem) = item, pickerItem.id == .articleOpeningMode else {
                    return nil
                }
                return pickerItem
            }
            .first
        )

        #expect(pickerItem.selectedValueTitle == SettingsLocalization.feedReaderOptionTitle)
        #expect(pickerItem.options.count == ArticleOpeningMode.allCases.count)
    }

    @Test
    func settingsScreenStateShowsArticleRetentionPickerWithUserFacingExplanation() throws {
        let state = SettingsScreenState.previewLoaded(
            snapshot: AppSettingsSnapshot(articleRetentionPolicy: .oneWeek)
        )

        let articleListSection = try #require(
            state.derivedViewState().sections.first(where: { $0.id == .articleList })
        )
        let pickerItem = try #require(
            articleListSection.items.compactMap { item -> SettingsPickerItemPresentation? in
                guard case .picker(let pickerItem) = item, pickerItem.id == .articleRetentionPolicy else {
                    return nil
                }
                return pickerItem
            }
            .first
        )

        #expect(pickerItem.title == SettingsLocalization.keepArchivedArticlesTitle)
        #expect(pickerItem.selectedValueTitle == SettingsLocalization.oneWeekOptionTitle)
        #expect(pickerItem.options.map(\.title) == [
            SettingsLocalization.noneOptionTitle,
            SettingsLocalization.twoDaysOptionTitle,
            SettingsLocalization.oneWeekOptionTitle,
            SettingsLocalization.twoWeeksOptionTitle,
            SettingsLocalization.oneMonthOptionTitle
        ])
        #expect(articleListSection.items.last?.id == .articleRetentionPolicy)
        #expect(articleListSection.footer == SettingsLocalization.articleListSectionFooter)
    }
}
