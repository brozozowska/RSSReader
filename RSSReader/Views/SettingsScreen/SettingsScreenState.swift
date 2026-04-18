import Foundation

enum SettingsScreenPhase: Equatable {
    case loading
    case loaded
    case failed(String)
}

struct SettingsScreenState {
    private(set) var phase: SettingsScreenPhase = .loading
    private(set) var settingsSnapshot = AppSettingsSnapshot()
    private(set) var sections: [SettingsScreenSectionPresentation] = []
    private(set) var presentedPicker: SettingsPickerItemPresentation? = nil

    mutating func beginLoading() {
        phase = .loading
        presentedPicker = nil
    }

    mutating func applyLoadedSnapshot(_ snapshot: AppSettingsSnapshot) {
        settingsSnapshot = snapshot
        sections = SettingsScreenPresentationBuilder.buildSections(from: snapshot)
        phase = .loaded
        presentedPicker = nil
    }

    mutating func applyLoadingFailure(_ message: String) {
        sections = []
        phase = .failed(message)
        presentedPicker = nil
    }

    mutating func presentPicker(for itemID: SettingsScreenItemID) {
        presentedPicker = pickerItem(for: itemID)
    }

    mutating func dismissPresentedPicker() {
        presentedPicker = nil
    }

    func derivedViewState() -> SettingsScreenViewState {
        SettingsScreenViewState(
            sections: sections,
            primaryLoadingState: primaryLoadingState,
            placeholder: placeholder,
            presentedPicker: presentedPicker
        )
    }

    static func previewLoading() -> SettingsScreenState {
        var state = SettingsScreenState()
        state.beginLoading()
        return state
    }

    static func previewFailed(message: String) -> SettingsScreenState {
        var state = SettingsScreenState()
        state.applyLoadingFailure(message)
        return state
    }

    static func previewLoaded(snapshot: AppSettingsSnapshot) -> SettingsScreenState {
        var state = SettingsScreenState()
        state.applyLoadedSnapshot(snapshot)
        return state
    }
}

private extension SettingsScreenState {
    var primaryLoadingState: SettingsScreenPrimaryLoadingState? {
        guard phase == .loading else {
            return nil
        }

        return SettingsScreenPrimaryLoadingState(title: "Loading Settings")
    }

    var placeholder: SettingsScreenPlaceholderState? {
        guard case .failed(let message) = phase else {
            return nil
        }

        return SettingsScreenPlaceholderState(
            title: "Unable to Load Settings",
            systemImage: "exclamationmark.triangle",
            description: message,
            actionTitle: "Retry"
        )
    }

    func pickerItem(for itemID: SettingsScreenItemID) -> SettingsPickerItemPresentation? {
        sections
            .flatMap(\.items)
            .first { $0.id == itemID }
            .flatMap { item in
                guard case .picker(let pickerItem) = item else {
                    return nil
                }
                return pickerItem
            }
    }
}
