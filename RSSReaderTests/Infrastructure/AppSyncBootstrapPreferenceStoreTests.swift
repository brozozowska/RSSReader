import Foundation
import Testing
@testable import RSSReader

@Suite("Infrastructure / AppSyncBootstrapPreferenceStore")
struct AppSyncBootstrapPreferenceStoreTests {
    @Test
    func currentBootPreferencePrefersNSUbiquitousKeyValueStoreAndBackfillsUserDefaults() {
        let userDefaults = TestBootstrapKeyValueStore(values: ["app.sync.bootstrapPreference": "disabled"])
        let ubiquitousStore = TestBootstrapUbiquitousStore(
            values: ["app.sync.bootstrapPreference": "enabled"],
            synchronizeResult: true
        )
        let logger = RecordingLogger()
        let store = AppSyncBootstrapPreferenceStore(
            userDefaults: userDefaults,
            ubiquitousStore: ubiquitousStore,
            logger: logger
        )

        let preference = store.currentBootPreference()

        #expect(preference == .enabled)
        #expect(userDefaults.string(forKey: "app.sync.bootstrapPreference") == AppSyncBootPreference.enabled.rawValue)
        #expect(ubiquitousStore.synchronizeCallCount == 1)
        #expect(logger.contains("Resolved sync bootstrap preference sync request; synchronize=true", level: .debug))
        #expect(
            logger.contains(
                "Resolved sync bootstrap preference from NSUbiquitousKeyValueStore: enabled",
                level: .info
            )
        )
    }

    @Test
    func currentBootPreferenceFallsBackToUserDefaultsWhenUbiquitousStoreHasNoValue() {
        let userDefaults = TestBootstrapKeyValueStore(values: ["app.sync.bootstrapPreference": "disabled"])
        let ubiquitousStore = TestBootstrapUbiquitousStore(values: [:], synchronizeResult: false)
        let logger = RecordingLogger()
        let store = AppSyncBootstrapPreferenceStore(
            userDefaults: userDefaults,
            ubiquitousStore: ubiquitousStore,
            logger: logger
        )

        let preference = store.currentBootPreference()

        #expect(preference == .disabled)
        #expect(ubiquitousStore.synchronizeCallCount == 1)
        #expect(logger.contains("Resolved sync bootstrap preference sync request; synchronize=false", level: .debug))
        #expect(logger.contains("Resolved sync bootstrap preference from UserDefaults: disabled", level: .info))
    }

    @Test
    func currentBootPreferenceIgnoresInvalidUbiquitousValueAndUsesUserDefaultsFallback() {
        let userDefaults = TestBootstrapKeyValueStore(values: ["app.sync.bootstrapPreference": "enabled"])
        let ubiquitousStore = TestBootstrapUbiquitousStore(
            values: ["app.sync.bootstrapPreference": "unexpected"],
            synchronizeResult: true
        )
        let logger = RecordingLogger()
        let store = AppSyncBootstrapPreferenceStore(
            userDefaults: userDefaults,
            ubiquitousStore: ubiquitousStore,
            logger: logger
        )

        let preference = store.currentBootPreference()

        #expect(preference == .enabled)
        #expect(logger.contains("Resolved sync bootstrap preference from UserDefaults: enabled", level: .info))
    }

    @Test
    func currentBootPreferenceReturnsNilWhenNoStorageContainsRecognizedValue() {
        let userDefaults = TestBootstrapKeyValueStore(values: ["app.sync.bootstrapPreference": "unexpected"])
        let ubiquitousStore = TestBootstrapUbiquitousStore(values: [:], synchronizeResult: true)
        let logger = RecordingLogger()
        let store = AppSyncBootstrapPreferenceStore(
            userDefaults: userDefaults,
            ubiquitousStore: ubiquitousStore,
            logger: logger
        )

        let preference = store.currentBootPreference()

        #expect(preference == nil)
        #expect(
            logger.contains(
                "No sync bootstrap preference found in NSUbiquitousKeyValueStore or UserDefaults",
                level: .info
            )
        )
    }

    @Test
    func saveBootPreferenceWritesToBothStoragesAndSynchronizesUbiquitousStore() {
        let userDefaults = TestBootstrapKeyValueStore()
        let ubiquitousStore = TestBootstrapUbiquitousStore(synchronizeResult: false)
        let logger = RecordingLogger()
        let store = AppSyncBootstrapPreferenceStore(
            userDefaults: userDefaults,
            ubiquitousStore: ubiquitousStore,
            logger: logger
        )

        store.saveBootPreference(.enabled)

        #expect(userDefaults.string(forKey: "app.sync.bootstrapPreference") == AppSyncBootPreference.enabled.rawValue)
        #expect(ubiquitousStore.string(forKey: "app.sync.bootstrapPreference") == AppSyncBootPreference.enabled.rawValue)
        #expect(ubiquitousStore.synchronizeCallCount == 1)
        #expect(
            logger.contains(
                "Saved sync bootstrap preference enabled to UserDefaults and NSUbiquitousKeyValueStore; synchronize=false",
                level: .info
            )
        )
    }
}

private final class TestBootstrapKeyValueStore: AppSyncBootstrapPreferenceKeyValueStoring {
    private var values: [String: String]

    init(values: [String: String] = [:]) {
        self.values = values
    }

    func string(forKey defaultName: String) -> String? {
        values[defaultName]
    }

    func set(_ value: Any?, forKey defaultName: String) {
        values[defaultName] = value as? String
    }
}

private final class TestBootstrapUbiquitousStore: AppSyncBootstrapPreferenceSynchronizing {
    private var values: [String: String]
    private let synchronizeResult: Bool
    private(set) var synchronizeCallCount = 0

    init(
        values: [String: String] = [:],
        synchronizeResult: Bool
    ) {
        self.values = values
        self.synchronizeResult = synchronizeResult
    }

    func string(forKey defaultName: String) -> String? {
        values[defaultName]
    }

    func set(_ value: Any?, forKey defaultName: String) {
        values[defaultName] = value as? String
    }

    func synchronize() -> Bool {
        synchronizeCallCount += 1
        return synchronizeResult
    }
}
