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
        #expect(viewState.sections.map(\.id) == [.reading, .articleList, .refresh, .sync, .advanced])
        #expect(state.settingsInput.defaultReaderMode == .browser)
        #expect(state.settingsInput.articleListSortOrder == .oldestFirst)
        #expect(state.settingsInput.iCloudSyncStatus == .disabled)
    }

    @Test
    func settingsScreenStatePresentsDefaultReaderModePickerFromLoadedSections() {
        var state = SettingsScreenState.previewLoaded(
            snapshot: AppSettingsSnapshot(defaultReaderMode: .reader)
        )

        state.presentPicker(for: .defaultReaderMode)

        let presentedPicker = state.derivedViewState().presentedPicker
        #expect(presentedPicker?.id == .defaultReaderMode)
        #expect(presentedPicker?.selectedValueTitle == "Reader Mode")
        #expect(presentedPicker?.options.count == ReaderMode.allCases.count)
    }
}
