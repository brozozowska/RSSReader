import Foundation
import Testing

@Suite("Localization / String Catalog Pluralization")
struct StringCatalogPluralizationTests {
    @Test
    func countBasedStringsUseNativePluralVariationsWithRussianCategories() throws {
        let strings = try Self.catalogStrings()

        for expectation in Self.russianPluralExpectations {
            #expect(
                Self.pluralValue(
                    in: strings,
                    key: expectation.key,
                    language: "ru",
                    category: expectation.category
                ) == expectation.value
            )
        }
    }

    @Test
    func englishPluralEntriesKeepOneAndOtherVariants() throws {
        let strings = try Self.catalogStrings()

        for expectation in Self.englishPluralExpectations {
            #expect(
                Self.pluralValue(
                    in: strings,
                    key: expectation.key,
                    language: "en",
                    category: expectation.category
                ) == expectation.value
            )
        }
    }

    @Test
    func legacyPluralSplitKeysAreRemovedFromCatalog() throws {
        let strings = try Self.catalogStrings()

        for key in Self.legacyPluralKeys {
            #expect(strings[key] == nil)
        }
    }

    private static let russianPluralExpectations: [PluralExpectation] = [
        .init(key: "reading.articles.subtitle.unread.count", category: "one", value: "%lld непрочитанная"),
        .init(key: "reading.articles.subtitle.unread.count", category: "few", value: "%lld непрочитанные"),
        .init(key: "reading.articles.subtitle.unread.count", category: "many", value: "%lld непрочитанных"),
        .init(key: "reading.articles.subtitle.unread.count", category: "other", value: "%lld непрочитанных"),
        .init(key: "reading.articles.refresh.multipleFeeds.failed.count", category: "one", value: "Не удалось обновить %lld ленту."),
        .init(key: "reading.articles.refresh.multipleFeeds.failed.count", category: "few", value: "Не удалось обновить %lld ленты."),
        .init(key: "reading.articles.refresh.multipleFeeds.failed.count", category: "many", value: "Не удалось обновить %lld лент."),
        .init(key: "settings.feedPortability.import.complete.importedFeedCount.count", category: "one", value: "Импортирована %lld лента"),
        .init(key: "settings.feedPortability.import.complete.importedFeedCount.count", category: "few", value: "Импортированы %lld ленты"),
        .init(key: "settings.feedPortability.import.complete.importedFeedCount.count", category: "many", value: "Импортировано %lld лент"),
        .init(key: "feedManagement.feedCount.count", category: "one", value: "%lld лента"),
        .init(key: "feedManagement.feedCount.count", category: "few", value: "%lld ленты"),
        .init(key: "feedManagement.feedCount.count", category: "many", value: "%lld лент")
    ]

    private static let englishPluralExpectations: [PluralExpectation] = [
        .init(key: "reading.articles.subtitle.unread.count", category: "one", value: "%lld Unread Item"),
        .init(key: "reading.articles.subtitle.unread.count", category: "other", value: "%lld Unread Items"),
        .init(key: "reading.articles.refresh.multipleFeeds.failed.count", category: "one", value: "%lld feed failed to refresh."),
        .init(key: "reading.articles.refresh.multipleFeeds.failed.count", category: "other", value: "%lld feeds failed to refresh."),
        .init(key: "feedManagement.feedCount.count", category: "one", value: "%lld feed"),
        .init(key: "feedManagement.feedCount.count", category: "other", value: "%lld feeds")
    ]

    private static let legacyPluralKeys = [
        "reading.articles.subtitle.unread.one",
        "reading.articles.subtitle.unread.few",
        "reading.articles.subtitle.unread.many",
        "reading.articles.subtitle.unread.format",
        "reading.articles.subtitle.starred.one",
        "reading.articles.subtitle.starred.few",
        "reading.articles.subtitle.starred.many",
        "reading.articles.subtitle.starred.format",
        "reading.articles.refresh.multipleFeeds.failed.one",
        "reading.articles.refresh.multipleFeeds.failed.few",
        "reading.articles.refresh.multipleFeeds.failed.many",
        "reading.articles.refresh.multipleFeeds.failed.format",
        "reading.articles.refresh.multipleFeedsWithFirstError.failed.one",
        "reading.articles.refresh.multipleFeedsWithFirstError.failed.few",
        "reading.articles.refresh.multipleFeedsWithFirstError.failed.many",
        "reading.articles.refresh.multipleFeedsWithFirstError.failed.format",
        "settings.feedPortability.import.complete.importedFeedCount.one",
        "settings.feedPortability.import.complete.importedFeedCount.few",
        "settings.feedPortability.import.complete.importedFeedCount.many",
        "settings.feedPortability.import.complete.importedFeedCount.other",
        "settings.feedPortability.import.complete.skippedEntryCount.one",
        "settings.feedPortability.import.complete.skippedEntryCount.few",
        "settings.feedPortability.import.complete.skippedEntryCount.many",
        "settings.feedPortability.import.complete.skippedEntryCount.other",
        "feedManagement.createFolder.placement.afterExisting.description.one",
        "feedManagement.createFolder.placement.afterExisting.description.few",
        "feedManagement.createFolder.placement.afterExisting.description.many",
        "feedManagement.createFolder.placement.afterExisting.description.format",
        "feedManagement.existingFeedCount.one",
        "feedManagement.existingFeedCount.few",
        "feedManagement.existingFeedCount.many",
        "feedManagement.existingFeedCount.format",
        "feedManagement.feedCount.one",
        "feedManagement.feedCount.few",
        "feedManagement.feedCount.many",
        "feedManagement.feedCount.format"
    ]

    private static func catalogStrings() throws -> [String: Any] {
        let catalogURL = try #require(localizableCatalogURL())
        let data = try Data(contentsOf: catalogURL)
        let catalog = try #require(
            try JSONSerialization.jsonObject(with: data) as? [String: Any]
        )
        return try #require(catalog["strings"] as? [String: Any])
    }

    private static func localizableCatalogURL() -> URL? {
        let fileManager = FileManager.default
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

        while directory.path != "/" {
            let candidate = directory.appendingPathComponent("RSSReader/Localizable.xcstrings")
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }

            directory.deleteLastPathComponent()
        }

        return nil
    }

    private static func pluralValue(
        in strings: [String: Any],
        key: String,
        language: String,
        category: String
    ) -> String? {
        guard
            let entry = strings[key] as? [String: Any],
            let localizations = entry["localizations"] as? [String: Any],
            let localization = localizations[language] as? [String: Any],
            let variations = localization["variations"] as? [String: Any],
            let plural = variations["plural"] as? [String: Any],
            let categoryEntry = plural[category] as? [String: Any],
            let stringUnit = categoryEntry["stringUnit"] as? [String: Any]
        else {
            return nil
        }

        return stringUnit["value"] as? String
    }
}

private struct PluralExpectation {
    let key: String
    let category: String
    let value: String
}
