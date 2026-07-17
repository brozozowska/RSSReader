enum SettingsScreenPresentationFormatter {
    static func articleOpeningModeTitle(_ mode: ArticleOpeningMode) -> String {
        switch mode {
        case .feedReader:
            SettingsLocalization.feedReaderOptionTitle
        case .safariView:
            SettingsLocalization.safariViewOptionTitle
        }
    }

    static func unreadArticleSortOrderTitle(_ order: UnreadArticleSortOrder) -> String {
        switch order {
        case .newestFirst:
            SettingsLocalization.newestFirstOptionTitle
        case .oldestFirst:
            SettingsLocalization.oldestFirstOptionTitle
        }
    }

    static func articleRetentionPolicyTitle(_ policy: ArticleRetentionPolicy) -> String {
        switch policy {
        case .currentFeedOnly:
            SettingsLocalization.currentFeedOnlyOptionTitle
        case .twoDays:
            SettingsLocalization.twoDaysOptionTitle
        case .oneWeek:
            SettingsLocalization.oneWeekOptionTitle
        case .twoWeeks:
            SettingsLocalization.twoWeeksOptionTitle
        case .oneMonth:
            SettingsLocalization.oneMonthOptionTitle
        }
    }

    static func refreshPreferenceTitle(_ preference: RefreshPreference) -> String {
        switch preference {
        case .manual:
            SettingsLocalization.manualOptionTitle
        case .every15Minutes:
            SettingsLocalization.every15MinutesOptionTitle
        case .hourly:
            SettingsLocalization.hourlyOptionTitle
        case .every6Hours:
            SettingsLocalization.every6HoursOptionTitle
        case .daily:
            SettingsLocalization.dailyOptionTitle
        }
    }

    static func articleBodyLinkOpeningPolicyTitle(_ policy: ArticleBodyLinkOpeningPolicy) -> String {
        switch policy {
        case .inAppBrowser:
            SettingsLocalization.inAppBrowserOptionTitle
        case .externalBrowser:
            SettingsLocalization.externalBrowserOptionTitle
        }
    }

    static func articleSourceLinkOpeningPolicyTitle(_ policy: ArticleSourceLinkOpeningPolicy) -> String {
        switch policy {
        case .inAppBrowser:
            SettingsLocalization.inAppBrowserOptionTitle
        case .externalBrowser:
            SettingsLocalization.externalBrowserOptionTitle
        }
    }

    static func readerAdjacentNavigationControlsModeTitle(_ mode: ReaderAdjacentNavigationControlsMode) -> String {
        switch mode {
        case .toolbarControlsOnly:
            SettingsLocalization.buttonsOptionTitle
        case .swipesOnly:
            SettingsLocalization.swipesOptionTitle
        case .swipesAndToolbarControls:
            SettingsLocalization.bothOptionTitle
        }
    }

    static func interfaceThemeModeTitle(_ mode: InterfaceThemeMode) -> String {
        switch mode {
        case .automaticLightDark:
            SettingsLocalization.automaticLightDarkOptionTitle
        case .automaticLightBlack:
            SettingsLocalization.automaticLightBlackOptionTitle
        case .light:
            SettingsLocalization.lightOptionTitle
        case .dark:
            SettingsLocalization.darkOptionTitle
        case .black:
            SettingsLocalization.blackOptionTitle
        }
    }
}
