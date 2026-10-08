import Foundation
import Observation

/// Device-local presentation preference; folder identity survives renames.
@MainActor
@Observable
final class SidebarFolderExpansionStore {
    private static let preferenceKey = "sidebar.collapsedFolderIDs"

    private(set) var collapsedFolderIDs: Set<UUID>
    private let userDefaults: UserDefaults?

    /// A nil backing store keeps previews and tests in memory.
    init(userDefaults: UserDefaults? = .standard) {
        self.userDefaults = userDefaults
        self.collapsedFolderIDs = Set(
            (userDefaults?.stringArray(forKey: Self.preferenceKey) ?? [])
                .compactMap(UUID.init(uuidString:))
        )
    }

    func toggleExpansion(folderID: UUID) {
        if collapsedFolderIDs.contains(folderID) {
            collapsedFolderIDs.remove(folderID)
        } else {
            collapsedFolderIDs.insert(folderID)
        }
        persist()
    }

    /// Only a successful, unfiltered entity snapshot may prune deleted folders.
    func reconcile(existingFolderIDs: Set<UUID>) {
        let retainedIDs = collapsedFolderIDs.intersection(existingFolderIDs)
        guard retainedIDs != collapsedFolderIDs else { return }
        collapsedFolderIDs = retainedIDs
        persist()
    }

    private func persist() {
        userDefaults?.set(
            collapsedFolderIDs.map(\.uuidString).sorted(),
            forKey: Self.preferenceKey
        )
    }
}
