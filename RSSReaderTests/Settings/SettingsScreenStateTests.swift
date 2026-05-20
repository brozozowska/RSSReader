import Foundation
import Testing
@testable import RSSReader

@Suite("Settings Screen / State")
@MainActor
struct SettingsScreenStateTests {
    @Test
    func settingsScreenStateBuildsLoadedViewStateFromSnapshot() {
        let snapshot = AppSettingsSnapshot(
            defaultReaderMode: .browser,
            selectedSourcesFilterRawValue: SourcesFilter.starred.rawValue,
            refreshIntervalPreference: .hourly,
            useiCloudSync: true,
            markAsReadOnOpen: false,
            sortMode: .publishedAtAscending
        )
        var state = SettingsScreenState()

        state.applyLoadedSnapshot(snapshot)
        let viewState = state.derivedViewState()

        #expect(viewState.primaryLoadingState == nil)
        #expect(viewState.placeholder == nil)
        #expect(viewState.sections.map(\.id) == [.appearance, .reading, .articleList, .updatesAndSync, .storage])
        #expect(state.settingsInput.defaultReaderMode == .browser)
        #expect(state.settingsInput.articleListSortOrder == .oldestFirst)
        #expect(state.settingsInput.iCloudSyncStatus == .disabled)
        #expect(state.hasArticleImageCache == false)
    }

    @Test
    func settingsScreenStateKeepsDefaultReaderModePickerInLoadedSections() throws {
        let state = SettingsScreenState.previewLoaded(
            snapshot: AppSettingsSnapshot(defaultReaderMode: .reader)
        )

        let readingSection = try #require(
            state.derivedViewState().sections.first(where: { $0.id == .reading })
        )
        let pickerItem = try #require(
            readingSection.items.compactMap { item -> SettingsPickerItemPresentation? in
                guard case .picker(let pickerItem) = item, pickerItem.id == .defaultReaderMode else {
                    return nil
                }
                return pickerItem
            }
            .first
        )

        #expect(pickerItem.selectedValueTitle == "Reader Mode")
        #expect(pickerItem.options.count == ReaderMode.allCases.count)
    }
}
