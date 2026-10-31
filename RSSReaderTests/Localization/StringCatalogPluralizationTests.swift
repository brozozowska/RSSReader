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

    @Test
    func allTargetLocalizationsCoverEveryCatalogEntryAndVariant() throws {
        let strings = try Self.catalogStrings()

        for (key, entry) in strings {
            let dictionary = try #require(entry as? [String: Any])
            let localizations = try #require(dictionary["localizations"] as? [String: Any])
            #expect(Set(localizations.keys) == Set(Self.supportedLanguages), "Locale set differs for \(key)")
            for language in Self.supportedLanguages where language != "en" {
                #expect(
                    Self.hasTranslatedLocalization(in: entry, language: language),
                    "Missing \(language) localization for \(key)"
                )
            }
        }
    }

    @Test
    func projectKnownRegionsMatchSupportedLanguages() throws {
        let projectFileURL = try #require(Self.projectFileURL())
        // Xcode's JSON project format allows trailing commas. Its development
        // language is implicit in supported localizations, unlike knownRegions.
        let project = try #require(try JSONSerialization.jsonObject(
            with: Data(contentsOf: projectFileURL), options: [.json5Allowed]
        ) as? [String: Any])
        let localizations = try #require(project["localizations"] as? [String: Any])
        let development = try #require(localizations["development"] as? String)
        let supported = try #require(localizations["supported"] as? [String])
        #expect(development == "en")
        #expect(Set(supported.filter { $0 != "Base" } + [development]) == Set(Self.supportedLanguages))
    }

    @Test
    func englishSourceAndAllTargetFormatArgumentsRemainCompatible() throws {
        for (key, untypedEntry) in try Self.catalogStrings() {
            let entry = try #require(untypedEntry as? [String: Any])
            let localizations = try #require(entry["localizations"] as? [String: Any])
            let source = try #require(localizations["en"] as? [String: Any])
            let sourceUnits = Self.stringUnits(in: source)
            #expect(!sourceUnits.isEmpty, "Missing English source: \(key)")
            let reference = try #require(sourceUnits.first?["value"] as? String)
            #expect(!reference.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            let signature = Self.formatArguments(in: reference)
            for language in Self.supportedLanguages {
                let localization = try #require(localizations[language] as? [String: Any])
                for (path, unit) in Self.stringVariants(in: localization) {
                    let value = try #require(unit["value"] as? String)
                    #expect(!value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                            "Empty source/translation for \(key), locale \(language), variant \(path)")
                    #expect(Self.compatibleFormatArguments(in: value, source: signature, variantPath: path),
                            "Format arguments differ for \(key), locale \(language): \(value)")
                }
            }
        }
    }

    @Test
    func bulkReadCopyUsesTheApprovedCurrentSelectionScope() throws {
        let strings = try Self.catalogStrings()
        for (key, english, russian) in [
            ("reading.articles.markAllRead.dialog.message",
             "This action will mark all articles in the current selection as read.",
             "Это действие отметит все статьи текущей выборки как прочитанные."),
            ("settings.articleList.askBeforeMarkingAllRead.subtitle",
             "Show a confirmation before marking all articles in the current selection as read.",
             "Показывать подтверждение перед отметкой всех статей текущей выборки как прочитанных.")
        ] {
            #expect(Self.localizedValue(in: strings, key: key, language: "en") == english)
            #expect(Self.localizedValue(in: strings, key: key, language: "ru") == russian)
        }
    }

    @Test
    func formatSignatureAllowsArgumentReorderingButDetectsTypeAndPositionChanges() {
        #expect(Self.formatArguments(in: "%1$lld feeds: %2$@")
                == Self.formatArguments(in: "%2$@ — %1$lld feeds"))
        #expect(Self.formatArguments(in: "%lld feeds: %@")
                == Self.formatArguments(in: "%2$@ — %1$lld feeds"))
        #expect(Self.formatArguments(in: "%% %@") == [1: "@"])
        #expect(Self.formatArguments(in: "%1$lld: %2$@") != Self.formatArguments(in: "%1$@: %2$lld"))
        // Arabic/Hebrew zero, one and two can express the count in words.
        let source = Self.formatArguments(in: "%1$lld feeds: %2$@")
        #expect(Self.compatibleFormatArguments(in: "One feed: %2$@", source: source, variantPath: "variations.plural.one"))
        #expect(!Self.compatibleFormatArguments(in: "One feed: %@", source: source, variantPath: "variations.plural.one"))
        #expect(!Self.compatibleFormatArguments(in: "Feeds: %2$@", source: source, variantPath: "variations.plural.other"))
    }

    @Test
    func feedHTTPErrorCopyCoversSupportedLocalesAndPreservesRetryDatePlaceholder() throws {
        let strings = try Self.catalogStrings()
        let keys = [
            "feedManagement.addFeed.preview.accessDenied.title",
            "feedManagement.addFeed.preview.accessDenied.detail",
            "feedManagement.addFeed.preview.rateLimited.title",
            "feedManagement.addFeed.preview.rateLimited.detail",
            "feedManagement.addFeed.preview.rateLimited.retryAt.format"
        ]
        for key in keys {
            let entry = try #require(strings[key] as? [String: Any])
            let localizations = try #require(entry["localizations"] as? [String: Any])
            #expect(Set(localizations.keys) == Set(Self.supportedLanguages))
            for language in Self.supportedLanguages {
                let value = try #require(Self.localizedValue(in: strings, key: key, language: language))
                #expect(!value.isEmpty)
                // The extracted English source is not a target translation.
                if language != "en" {
                    #expect(Self.hasTranslatedLocalization(in: entry, language: language))
                }
                if key.hasSuffix("retryAt.format") {
                    #expect(value.components(separatedBy: "%@").count == 2)
                    #expect(value.contains("429"))
                }
                if key.hasSuffix("accessDenied.detail") { #expect(value.contains("403")) }
            }
        }
    }

    @Test
    func articleRetentionCopyMatchesApprovedRussianContract() throws {
        let strings = try Self.catalogStrings()

        #expect(
            Self.localizedValue(
                in: strings,
                key: "settings.articleList.section.footer",
                language: "ru"
            ) == "Статьи остаются на устройстве, пока лента продолжает их возвращать. Если при обновлении статья пропала из выдачи, вариант «Пока есть в выдаче» удалит её сразу, а варианты со сроком — по истечении выбранного срока с этого обновления. Для каждой ленты сохраняется не более 2 000 статей. Статьи в Избранном хранятся, пока вы не удалите их из Избранного."
        )
        #expect(
            Self.localizedValue(
                in: strings,
                key: "settings.option.retention.currentFeedOnly",
                language: "ru"
            ) == "Пока есть в выдаче"
        )
    }

    @Test
    func articleRetentionCopyCoversEverySupportedLocaleAndUpdatedTranslatorContext() throws {
        let strings = try Self.catalogStrings()
        let keys = [
            "settings.articleList.section.footer",
            "settings.option.retention.currentFeedOnly"
        ]

        for key in keys {
            let entry = try #require(strings[key] as? [String: Any])
            let localizations = try #require(entry["localizations"] as? [String: Any])

            #expect(Set(localizations.keys) == Set(Self.supportedLanguages))
            for language in Self.supportedLanguages {
                #expect(Self.hasTranslatedLocalization(in: entry, language: language))
            }
        }

        let footerEntry = try #require(strings[keys[0]] as? [String: Any])
        let optionEntry = try #require(strings[keys[1]] as? [String: Any])
        #expect(
            footerEntry["comment"] as? String
                == "Footer explaining that articles are kept while returned by a feed, timed retention starts when an article disappears during an update, no more than 2,000 articles are kept per feed, and articles in Starred are kept until removed from Starred."
        )
        #expect(
            optionEntry["comment"] as? String
                == "Picker option that removes an article immediately when it no longer appears in the feed's returned article list."
        )
    }

    @Test
    func emptyFeedsCopyMatchesApprovedDeviceNeutralContract() throws {
        let strings = try Self.catalogStrings()
        let key = "sidebar.empty.description"
        let entry = try #require(strings[key] as? [String: Any])
        let localizations = try #require(entry["localizations"] as? [String: Any])

        #expect(
            Self.localizedValue(in: strings, key: key, language: "en")
                == "Add your first feed to start reading articles."
        )
        #expect(
            Self.localizedValue(in: strings, key: key, language: "ru")
                == "Добавьте первую ленту, чтобы начать читать статьи."
        )
        #expect(Set(localizations.keys) == Set(Self.supportedLanguages))
        for language in Self.supportedLanguages {
            #expect(Self.hasTranslatedLocalization(in: entry, language: language))
        }
        #expect(
            entry["comment"] as? String
                == "Device-neutral empty state description inviting the user to add their first feed and start reading articles."
        )
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

    private static let supportedLanguages = [
        "ar", "de", "en", "es", "fa", "fr", "he", "it", "ja", "ko", "pt-BR", "ru", "ur", "zh-Hans"
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

    private static func projectFileURL() -> URL? {
        let fileManager = FileManager.default
        var directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()

        while directory.path != "/" {
            let candidate = directory.appendingPathComponent("RSSReader.xcodeproj/project.xcproj")
            if fileManager.fileExists(atPath: candidate.path) {
                return candidate
            }

            directory.deleteLastPathComponent()
        }

        return nil
    }

    private static func hasTranslatedLocalization(in entry: Any, language: String) -> Bool {
        guard
            let entry = entry as? [String: Any],
            let localizations = entry["localizations"] as? [String: Any],
            let localization = localizations[language] as? [String: Any]
        else {
            return false
        }

        let units = Self.stringUnits(in: localization)
        return !units.isEmpty && units.allSatisfy { unit in
            guard let value = unit["value"] as? String else { return false }
            return Self.isUsableTranslationState(unit["state"] as? String)
                && !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private static func stringUnits(in dictionary: [String: Any]) -> [[String: Any]] {
        stringVariants(in: dictionary).map { $0.unit }
    }

    private static func stringVariants(in dictionary: [String: Any], path: String = "") -> [(path: String, unit: [String: Any])] {
        var result: [(path: String, unit: [String: Any])] = []
        if let unit = dictionary["stringUnit"] as? [String: Any] { result.append((path, unit)) }
        for (key, value) in dictionary where key != "stringUnit" {
            if let child = value as? [String: Any] {
                result += stringVariants(in: child, path: path.isEmpty ? key : "\(path).\(key)")
            }
        }
        return result
    }

    private static func compatibleFormatArguments(in value: String, source: [Int: String], variantPath: String) -> Bool {
        let actual = formatArguments(in: value)
        if actual == source { return true }
        let implicitCount = ["zero", "one", "two"].contains { variantPath == "variations.plural.\($0)" }
        let countArguments = source.filter { ["d", "u", "ld", "lu", "lld", "llu"].contains($0.value) }
        guard implicitCount, countArguments.count == 1, let position = countArguments.keys.first else { return false }
        var withoutCount = source
        withoutCount.removeValue(forKey: position)
        return actual == withoutCount
    }

    private static func formatArguments(in value: String) -> [Int: String] {
        let text = value.replacingOccurrences(of: "%%", with: "")
        let regex = try! NSRegularExpression(pattern: #"%(?:(\d+)\$)?[-+ #0]*\d*(?:\.\d+)?(hh|ll|h|l|z|t|j)?([@diuoxXfFeEgGaAcCsSp])"#)
        let range = NSRange(text.startIndex..., in: text)
        var result: [Int: String] = [:]
        var nextPosition = 1
        for match in regex.matches(in: text, range: range) {
            let position = Range(match.range(at: 1), in: text).flatMap { Int(text[$0]) } ?? nextPosition
            let modifier = Range(match.range(at: 2), in: text).map { String(text[$0]) } ?? ""
            let type = Range(match.range(at: 3), in: text).map { String(text[$0]) } ?? ""
            result[position] = modifier + type
            nextPosition += 1
        }
        return result
    }

    private static func isUsableTranslationState(_ state: String?) -> Bool {
        // StringCatalogEdit records tool-authored translations as machine_translated.
        state == "translated" || state == "machine_translated"
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

    private static func localizedValue(
        in strings: [String: Any],
        key: String,
        language: String
    ) -> String? {
        guard
            let entry = strings[key] as? [String: Any],
            let localizations = entry["localizations"] as? [String: Any],
            let localization = localizations[language] as? [String: Any],
            let stringUnit = localization["stringUnit"] as? [String: Any]
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
