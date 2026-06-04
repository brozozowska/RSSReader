enum SettingsScreenPresentationFormatter {
    static func articleOpeningModeTitle(_ mode: ArticleOpeningMode) -> String {
        switch mode {
        case .feedReader:
            "Feed Reader"
        case .safariView:
            "Safari View"
        }
    }

    static func unreadArticleSortOrderTitle(_ order: UnreadArticleSortOrder) -> String {
        switch order {
        case .newestFirst:
            "Newest First"
        case .oldestFirst:
            "Oldest First"
        }
    }

    static func articleRetentionPolicyTitle(_ policy: ArticleRetentionPolicy) -> String {
        switch policy {
        case .currentFeedOnly:
            "None"
        case .twoDays:
            "2 Days"
        case .oneWeek:
            "1 Week"
        case .twoWeeks:
            "2 Weeks"
        case .oneMonth:
            "1 Month"
        }
    }

    static func refreshPreferenceTitle(_ preference: RefreshPreference) -> String {
        switch preference {
        case .manual:
            "Manual"
        case .every15Minutes:
            "Every 15 Minutes"
        case .hourly:
            "Hourly"
        case .every6Hours:
            "Every 6 Hours"
        case .daily:
            "Daily"
        }
    }

    static func articleBodyLinkOpeningPolicyTitle(_ policy: ArticleBodyLinkOpeningPolicy) -> String {
        switch policy {
        case .inAppBrowser:
            "In-App Browser"
        case .externalBrowser:
            "External Browser"
        }
    }

    static func articleSourceLinkOpeningPolicyTitle(_ policy: ArticleSourceLinkOpeningPolicy) -> String {
        switch policy {
        case .inAppBrowser:
            "In-App Browser"
        case .externalBrowser:
            "External Browser"
        }
    }

    static func readerAdjacentNavigationControlsModeTitle(_ mode: ReaderAdjacentNavigationControlsMode) -> String {
        switch mode {
        case .toolbarControlsOnly:
            "Buttons"
        case .swipesOnly:
            "Swipes"
        case .swipesAndToolbarControls:
            "Both"
        }
    }

    static func interfaceThemeModeTitle(_ mode: InterfaceThemeMode) -> String {
        switch mode {
        case .automaticLightDark:
            "Automatic Light/Dark"
        case .automaticLightBlack:
            "Automatic Light/Black"
        case .light:
            "Light"
        case .dark:
            "Dark"
        case .black:
            "Black"
        }
    }
}
