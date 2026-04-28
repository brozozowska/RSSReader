import Foundation

protocol AppSyncBootstrapPreferenceStoring {
    func currentBootPreference() -> AppSyncBootPreference?
    func saveBootPreference(_ preference: AppSyncBootPreference)
}

struct AppSyncBootstrapPreferenceStore: AppSyncBootstrapPreferenceStoring {
    private static let preferenceKey = "app.sync.bootstrapPreference"

    let userDefaults: UserDefaults
    let ubiquitousStore: NSUbiquitousKeyValueStore
    let logger: Logging

    init(
        userDefaults: UserDefaults = .standard,
        ubiquitousStore: NSUbiquitousKeyValueStore = .default,
        logger: Logging = ConsoleLogger()
    ) {
        self.userDefaults = userDefaults
        self.ubiquitousStore = ubiquitousStore
        self.logger = logger
    }

    func currentBootPreference() -> AppSyncBootPreference? {
        let synchronizationSucceeded = ubiquitousStore.synchronize()
        logger.debug(
            "Resolved sync bootstrap preference sync request; synchronize=\(synchronizationSucceeded)"
        )

        if let rawValue = ubiquitousStore.string(forKey: Self.preferenceKey),
           let preference = AppSyncBootPreference(rawValue: rawValue) {
            userDefaults.set(rawValue, forKey: Self.preferenceKey)
            logger.info(
                "Resolved sync bootstrap preference from NSUbiquitousKeyValueStore: \(preference.rawValue)"
            )
            return preference
        }

        if let rawValue = userDefaults.string(forKey: Self.preferenceKey),
           let preference = AppSyncBootPreference(rawValue: rawValue) {
            logger.info("Resolved sync bootstrap preference from UserDefaults: \(preference.rawValue)")
            return preference
        }

        logger.info("No sync bootstrap preference found in NSUbiquitousKeyValueStore or UserDefaults")
        return nil
    }

    func saveBootPreference(_ preference: AppSyncBootPreference) {
        let rawValue = preference.rawValue
        userDefaults.set(rawValue, forKey: Self.preferenceKey)
        ubiquitousStore.set(rawValue, forKey: Self.preferenceKey)
        let synchronizationSucceeded = ubiquitousStore.synchronize()
        logger.info(
            "Saved sync bootstrap preference \(rawValue) to UserDefaults and NSUbiquitousKeyValueStore; synchronize=\(synchronizationSucceeded)"
        )
    }
}
