import Foundation

enum SettingsLocalization {
    static let screenTitle = String(
        localized: "settings.screen.title",
        defaultValue: "Settings",
        comment: "Navigation title for the app settings screen."
    )
    static let closeSettingsAccessibilityLabel = String(
        localized: "settings.accessibility.close",
        defaultValue: "Close Settings",
        comment: "Accessibility label for the close button on the settings screen."
    )
    static let applySettingsAccessibilityLabel = String(
        localized: "settings.accessibility.apply",
        defaultValue: "Apply Settings",
        comment: "Accessibility label for the apply button on the settings screen."
    )
    static let loadingTitle = String(
        localized: "settings.loading.title",
        defaultValue: "Loading Settings",
        comment: "Loading state title shown while settings are fetched."
    )
    static let loadFailureTitle = String(
        localized: "settings.loadFailure.title",
        defaultValue: "Unable to Load Settings",
        comment: "Placeholder title shown when settings cannot be loaded."
    )
    static let retryActionTitle = CommonLocalization.retryAction
    static let unavailableMessage = String(
        localized: "settings.unavailable.message",
        defaultValue: "Settings are unavailable in the current app environment.",
        comment: "Fallback error message when settings services are unavailable."
    )
    static let genericLoadFailureMessage = String(
        localized: "settings.loadFailure.genericMessage",
        defaultValue: "Unable to load settings right now. Try again.",
        comment: "Generic error message shown after a settings loading failure."
    )

    static let appearanceSectionTitle = String(
        localized: "settings.appearance.section.title",
        defaultValue: "Appearance",
        comment: "Settings section title for appearance options."
    )
    static let appearanceSectionFooter = String(
        localized: "settings.appearance.section.footer",
        defaultValue: "Choose which theme is shown in the app interface.",
        comment: "Footer explaining the appearance settings section."
    )
    static let themePickerTitle = String(
        localized: "settings.appearance.theme.title",
        defaultValue: "Theme",
        comment: "Picker title for the interface theme setting."
    )
    static let readingSectionTitle = String(
        localized: "settings.reading.section.title",
        defaultValue: "Reading",
        comment: "Settings section title for reading options."
    )
    static let readingSectionFooter = String(
        localized: "settings.reading.section.footer",
        defaultValue: "Choose whether opening an article shows Reader or the in-app browser. Open Original Article controls opening the article page, and Open Article Links controls opening links inside an article. Adjacent Navigation lets you show or hide additional buttons in the interface.",
        comment: "Footer explaining reading and link opening settings."
    )
    static let openArticlesTitle = String(
        localized: "settings.reading.openArticles.title",
        defaultValue: "Open Articles",
        comment: "Picker title for choosing how articles open."
    )
    static let openOriginalArticleTitle = String(
        localized: "settings.reading.openOriginalArticle.title",
        defaultValue: "Open Original Article",
        comment: "Picker title for choosing how source article links open."
    )
    static let openArticleLinksTitle = String(
        localized: "settings.reading.openArticleLinks.title",
        defaultValue: "Open Article Links",
        comment: "Picker title for choosing how links inside article text open."
    )
    static let adjacentNavigationTitle = String(
        localized: "settings.reading.adjacentNavigation.title",
        defaultValue: "Adjacent Navigation",
        comment: "Picker title for choosing adjacent article navigation controls."
    )
    static let markReadOnOpenTitle = String(
        localized: "settings.reading.markReadOnOpen.title",
        defaultValue: "Mark Read on Open",
        comment: "Toggle title for marking articles read when opened."
    )
    static let markReadOnOpenSubtitle = String(
        localized: "settings.reading.markReadOnOpen.subtitle",
        defaultValue: "Automatically mark an article as read when it is opened.",
        comment: "Toggle subtitle explaining mark-read-on-open behavior."
    )
    static let articleListSectionTitle = String(
        localized: "settings.articleList.section.title",
        defaultValue: "Article List",
        comment: "Settings section title for article list options."
    )
    static let articleListSectionFooter = String(
        localized: "settings.articleList.section.footer",
        defaultValue: "\"None\" removes an article from the list as soon as it disappears from its feed. Other options keep the article for the selected time after it disappears from the feed.",
        comment: "Footer explaining archived article retention settings."
    )
    static let sortUnreadArticlesTitle = String(
        localized: "settings.articleList.sortUnread.title",
        defaultValue: "Sort Unread Articles",
        comment: "Picker title for unread article sort order."
    )
    static let askBeforeMarkingAllReadTitle = String(
        localized: "settings.articleList.askBeforeMarkingAllRead.title",
        defaultValue: "Ask Before Marking All Read",
        comment: "Toggle title for asking before marking all visible articles read."
    )
    static let askBeforeMarkingAllReadSubtitle = String(
        localized: "settings.articleList.askBeforeMarkingAllRead.subtitle",
        defaultValue: "Show a confirmation before marking all visible articles as read.",
        comment: "Toggle subtitle explaining confirmation before marking all visible articles read."
    )
    static let keepArchivedArticlesTitle = String(
        localized: "settings.articleList.keepArchivedArticles.title",
        defaultValue: "Keep Archived Articles",
        comment: "Picker title for archived article retention."
    )
    static let updatesSyncSectionTitle = String(
        localized: "settings.updatesSync.section.title",
        defaultValue: "Updates & Sync",
        comment: "Settings section title for background refresh and iCloud sync options."
    )
    static let backgroundRefreshTitle = String(
        localized: "settings.updatesSync.backgroundRefresh.title",
        defaultValue: "Background Refresh",
        comment: "Picker title for background refresh interval."
    )
    static let enableICloudSyncTitle = String(
        localized: "settings.updatesSync.enableICloudSync.title",
        defaultValue: "Enable iCloud Sync",
        comment: "Toggle title for enabling iCloud sync."
    )
    static let currentStatusTitle = String(
        localized: "settings.updatesSync.currentStatus.title",
        defaultValue: "Current Status",
        comment: "Status row title for current iCloud sync status."
    )
    static let iCloudSyncPreferenceEnabledSubtitle = String(
        localized: "settings.updatesSync.preference.enabled.subtitle",
        defaultValue: "Applies on next launch. Supported data will sync through iCloud when available.",
        comment: "Subtitle for enabled iCloud sync preference."
    )
    static let iCloudSyncPreferenceDisabledSubtitle = String(
        localized: "settings.updatesSync.preference.disabled.subtitle",
        defaultValue: "Applies on next launch. When this setting is disabled, all syncable data stays on the device.",
        comment: "Subtitle for disabled iCloud sync preference."
    )
    static func iCloudSyncPreferenceFallbackSubtitle(reason: String) -> String {
        let format = String(localized:
            "settings.updatesSync.preference.fallback.subtitle",
            defaultValue: "Saved for the next launch. This session keeps using local data because %@.",
            comment: "Subtitle for enabled iCloud sync preference when this launch uses local-only fallback. Placeholder is the fallback reason."
        )
        return CommonLocalization.localizedTemplate(format, reason)
    }
    static let iCloudScopeAccountFooter = String(
        localized: "settings.updatesSync.footer.account",
        defaultValue: "App settings, feeds, folders, articles, and their states sync across devices using iCloud and your Apple ID. Article images and feed icons are stored separately on each device. Changing the sync setting applies on the next app launch.",
        comment: "Footer explaining iCloud sync scope and relaunch behavior in the Updates & Sync settings section."
    )
    static let iCloudScopeRelaunchFooter = String(
        localized: "settings.updatesSync.footer.relaunch",
        defaultValue: "Changing the sync preference applies on the next app launch.",
        comment: "Footer sentence explaining sync preference relaunch behavior."
    )
    static let iCloudScopeFallbackFooter = String(
        localized: "settings.updatesSync.footer.fallback",
        defaultValue: "Sync will try again on the next launch when iCloud is available.",
        comment: "Footer sentence shown when the current launch uses local-only sync fallback."
    )
    static let notificationsSectionTitle = String(
        localized: "settings.notifications.section.title",
        defaultValue: "Notifications",
        comment: "Settings section title for notification-related options."
    )
    static let notificationsSectionFooter = String(
        localized: "settings.notifications.section.footer",
        defaultValue: "The app does not send notifications, but iOS still requires notification permission to show a badge on the app icon.",
        comment: "Footer explaining notification permission usage for the app icon badge."
    )
    static let appIconBadgeTitle = String(
        localized: "settings.notifications.appIconBadge.title",
        defaultValue: "App Icon Badge",
        comment: "Toggle title for showing unread article count on the app icon."
    )
    static let appIconBadgeSubtitle = String(
        localized: "settings.notifications.appIconBadge.subtitle",
        defaultValue: "Show the unread article count on the app icon.",
        comment: "Toggle subtitle explaining the app icon badge setting."
    )
    static let feedPortabilitySectionTitle = String(
        localized: "settings.feedPortability.section.title",
        defaultValue: "Feed Portability",
        comment: "Settings section title for feed import and export."
    )
    static let feedPortabilitySectionFooter = String(
        localized: "settings.feedPortability.section.footer",
        defaultValue: "Import and export OPML files to move feeds between apps.",
        comment: "Footer explaining feed portability import and export actions."
    )
    static let importOPMLTitle = String(
        localized: "settings.feedPortability.import.title",
        defaultValue: "Import OPML",
        comment: "Button title for importing an OPML file."
    )
    static let importOPMLSubtitle = String(
        localized: "settings.feedPortability.import.subtitle",
        defaultValue: "Preview feeds before adding them.",
        comment: "Button subtitle for importing an OPML file."
    )
    static let exportOPMLTitle = String(
        localized: "settings.feedPortability.export.title",
        defaultValue: "Export OPML",
        comment: "Button title for exporting an OPML file."
    )
    static let exportOPMLSubtitle = String(
        localized: "settings.feedPortability.export.subtitle",
        defaultValue: "Save active feeds as an OPML file.",
        comment: "Button subtitle for exporting an OPML file."
    )
    static let storageSectionTitle = String(
        localized: "settings.storage.section.title",
        defaultValue: "Storage",
        comment: "Settings section title for storage cleanup actions."
    )
    static let clearArchivedArticlesTitle = String(
        localized: "settings.storage.clearArchivedArticles.title",
        defaultValue: "Clear Archived Articles",
        comment: "Button title for deleting archived articles."
    )
    static let clearArchivedArticlesSubtitle = String(
        localized: "settings.storage.clearArchivedArticles.subtitle",
        defaultValue: "Remove archived articles except starred ones from this device and iCloud.",
        comment: "Button subtitle explaining archived article cleanup."
    )
    static let clearArticleImageCacheTitle = String(
        localized: "settings.storage.clearArticleImageCache.title",
        defaultValue: "Clear Article Image Cache",
        comment: "Button title for deleting cached article images."
    )
    static let clearArticleImageCacheSubtitle = String(
        localized: "settings.storage.clearArticleImageCache.subtitle",
        defaultValue: "Remove article images saved on this device.",
        comment: "Button subtitle explaining article image cache cleanup."
    )
    static let clearFeedIconCacheTitle = String(
        localized: "settings.storage.clearFeedIconCache.title",
        defaultValue: "Clear Feed Icon Cache",
        comment: "Button title for deleting cached feed icons."
    )
    static let clearFeedIconCacheSubtitle = String(
        localized: "settings.storage.clearFeedIconCache.subtitle",
        defaultValue: "Remove feed icons saved on this device.",
        comment: "Button subtitle explaining feed icon cache cleanup."
    )
    static let feedReaderOptionTitle = String(
        localized: "settings.option.articleOpeningMode.feedReader",
        defaultValue: "Reader",
        comment: "Picker option title for opening articles in the app reader."
    )
    static let safariViewOptionTitle = String(
        localized: "settings.option.articleOpeningMode.safariView",
        defaultValue: "Safari View",
        comment: "Picker option title for opening articles in SFSafariViewController."
    )
    static let newestFirstOptionTitle = String(
        localized: "settings.option.sort.newestFirst",
        defaultValue: "Newest First",
        comment: "Picker option title for newest-first sort order."
    )
    static let oldestFirstOptionTitle = String(
        localized: "settings.option.sort.oldestFirst",
        defaultValue: "Oldest First",
        comment: "Picker option title for oldest-first sort order."
    )
    static let noneOptionTitle = String(
        localized: "settings.option.retention.none",
        defaultValue: "None",
        comment: "Picker option title for no archived article retention."
    )
    static let twoDaysOptionTitle = String(
        localized: "settings.option.retention.twoDays",
        defaultValue: "2 Days",
        comment: "Picker option title for two-day archived article retention."
    )
    static let oneWeekOptionTitle = String(
        localized: "settings.option.retention.oneWeek",
        defaultValue: "1 week",
        comment: "Picker option title for one-week archived article retention."
    )
    static let twoWeeksOptionTitle = String(
        localized: "settings.option.retention.twoWeeks",
        defaultValue: "2 Weeks",
        comment: "Picker option title for two-week archived article retention."
    )
    static let oneMonthOptionTitle = String(
        localized: "settings.option.retention.oneMonth",
        defaultValue: "1 Month",
        comment: "Picker option title for one-month archived article retention."
    )
    static let manualOptionTitle = String(
        localized: "settings.option.refresh.manual",
        defaultValue: "Manual",
        comment: "Picker option title for manual refresh."
    )
    static let every15MinutesOptionTitle = String(
        localized: "settings.option.refresh.every15Minutes",
        defaultValue: "Every 15 Minutes",
        comment: "Picker option title for 15-minute background refresh."
    )
    static let hourlyOptionTitle = String(
        localized: "settings.option.refresh.hourly",
        defaultValue: "Hourly",
        comment: "Picker option title for hourly background refresh."
    )
    static let every6HoursOptionTitle = String(
        localized: "settings.option.refresh.every6Hours",
        defaultValue: "Every 6 Hours",
        comment: "Picker option title for six-hour background refresh."
    )
    static let dailyOptionTitle = String(
        localized: "settings.option.refresh.daily",
        defaultValue: "Daily",
        comment: "Picker option title for daily background refresh."
    )
    static let inAppBrowserOptionTitle = String(
        localized: "settings.option.linkOpening.inAppBrowser",
        defaultValue: "In-app browser",
        comment: "Picker option title for opening links in the in-app browser."
    )
    static let externalBrowserOptionTitle = String(
        localized: "settings.option.linkOpening.externalBrowser",
        defaultValue: "External Browser",
        comment: "Picker option title for opening links in the external browser."
    )
    static let buttonsOptionTitle = String(
        localized: "settings.option.adjacentNavigation.buttons",
        defaultValue: "Buttons",
        comment: "Picker option title for toolbar-only adjacent article navigation."
    )
    static let swipesOptionTitle = String(
        localized: "settings.option.adjacentNavigation.swipes",
        defaultValue: "Swipes",
        comment: "Picker option title for swipe-only adjacent article navigation."
    )
    static let bothOptionTitle = String(
        localized: "settings.option.adjacentNavigation.both",
        defaultValue: "Both",
        comment: "Picker option title for both swipe and toolbar adjacent article navigation."
    )
    static let automaticLightDarkOptionTitle = String(
        localized: "settings.option.theme.automaticLightDark",
        defaultValue: "Automatic Light/Dark",
        comment: "Picker option title for automatic light and dark themes."
    )
    static let automaticLightBlackOptionTitle = String(
        localized: "settings.option.theme.automaticLightBlack",
        defaultValue: "Automatic Light/Black",
        comment: "Picker option title for automatic light and black themes."
    )
    static let lightOptionTitle = String(
        localized: "settings.option.theme.light",
        defaultValue: "Light",
        comment: "Picker option title for light theme."
    )
    static let darkOptionTitle = String(
        localized: "settings.option.theme.dark",
        defaultValue: "Dark",
        comment: "Picker option title for dark theme."
    )
    static let blackOptionTitle = String(
        localized: "settings.option.theme.black",
        defaultValue: "Black",
        comment: "Picker option title for black theme."
    )
    static let syncStatusOffTitle = String(
        localized: "settings.syncStatus.off.title",
        defaultValue: "Off",
        comment: "Value title for disabled iCloud sync status."
    )
    static let syncStatusUnavailableTitle = String(
        localized: "settings.syncStatus.unavailable.title",
        defaultValue: "Status Unavailable",
        comment: "Value title when live iCloud sync status cannot be read."
    )
    static let syncStatusCheckingTitle = String(
        localized: "settings.syncStatus.checking.title",
        defaultValue: "Checking",
        comment: "Value title while checking iCloud account status."
    )
    static let syncStatusReadyTitle = String(
        localized: "settings.syncStatus.ready.title",
        defaultValue: "Ready",
        comment: "Value title when iCloud sync is ready."
    )
    static let syncStatusSyncingTitle = String(
        localized: "settings.syncStatus.syncing.title",
        defaultValue: "Syncing",
        comment: "Value title while iCloud sync is active."
    )
    static let syncStatusPreparingTitle = String(
        localized: "settings.syncStatus.preparing.title",
        defaultValue: "Preparing",
        comment: "Value title while preparing iCloud sync."
    )
    static let syncStatusImportingTitle = String(
        localized: "settings.syncStatus.importing.title",
        defaultValue: "Importing",
        comment: "Value title while applying iCloud changes."
    )
    static let syncStatusUploadingTitle = String(
        localized: "settings.syncStatus.uploading.title",
        defaultValue: "Uploading",
        comment: "Value title while uploading changes to iCloud."
    )
    static let syncStatusNoAccountTitle = String(
        localized: "settings.syncStatus.noAccount.title",
        defaultValue: "Sign In Required",
        comment: "Value title when iCloud sign-in is required."
    )
    static let syncStatusRestrictedTitle = String(
        localized: "settings.syncStatus.restricted.title",
        defaultValue: "Restricted",
        comment: "Value title when iCloud access is restricted."
    )
    static let syncStatusTemporarilyUnavailableTitle = String(
        localized: "settings.syncStatus.temporarilyUnavailable.title",
        defaultValue: "Temporarily Unavailable",
        comment: "Value title when iCloud account is temporarily unavailable."
    )
    static let syncStatusCouldNotDetermineTitle = String(
        localized: "settings.syncStatus.couldNotDetermine.title",
        defaultValue: "Account Unavailable",
        comment: "Value title when iCloud account status could not be determined."
    )
    static let syncStatusErrorTitle = String(
        localized: "settings.syncStatus.error.title",
        defaultValue: "Error",
        comment: "Value title for failed iCloud sync status."
    )
    static let syncFallbackNoAccountSubtitle = String(
        localized: "settings.syncStatus.fallback.noAccount.subtitle",
        defaultValue: "Sync is enabled, but this launch cannot use iCloud because the device is not signed in. Relaunch after signing in.",
        comment: "Status subtitle for local-only fallback when iCloud sign-in is missing."
    )
    static let syncFallbackRestrictedSubtitle = String(
        localized: "settings.syncStatus.fallback.restricted.subtitle",
        defaultValue: "Sync is enabled, but this launch cannot use iCloud because access is restricted on this device. Relaunch after the restriction is removed.",
        comment: "Status subtitle for local-only fallback when iCloud access is restricted."
    )
    static let syncFallbackTemporarilyUnavailableSubtitle = String(
        localized: "settings.syncStatus.fallback.temporarilyUnavailable.subtitle",
        defaultValue: "Sync is enabled, but this launch cannot use iCloud because the current account is temporarily unavailable. Relaunch after iCloud becomes available.",
        comment: "Status subtitle for local-only fallback when iCloud is temporarily unavailable."
    )
    static let syncFallbackCouldNotDetermineSubtitle = String(
        localized: "settings.syncStatus.fallback.couldNotDetermine.subtitle",
        defaultValue: "Sync is enabled, but this launch could not confirm iCloud availability. Relaunch after iCloud becomes available.",
        comment: "Status subtitle for local-only fallback when iCloud availability could not be confirmed."
    )
    static let syncDisabledSubtitle = String(
        localized: "settings.syncStatus.disabled.subtitle",
        defaultValue: "iCloud sync is off.",
        comment: "Status subtitle for disabled iCloud sync."
    )
    static let syncStatusUnavailableSubtitle = String(
        localized: "settings.syncStatus.unavailable.subtitle",
        defaultValue: "The current app session could not read the live iCloud sync status.",
        comment: "Status subtitle when live iCloud sync status cannot be read."
    )
    static let syncCheckingAccountSubtitle = String(
        localized: "settings.syncStatus.checking.subtitle",
        defaultValue: "The app is checking the current iCloud account and CloudKit session status.",
        comment: "Status subtitle while checking iCloud account and CloudKit session status."
    )
    static let syncReadySubtitle = String(
        localized: "settings.syncStatus.ready.subtitle",
        defaultValue: "iCloud sync is available for the Apple ID currently signed in on this device.",
        comment: "Status subtitle when iCloud sync is ready."
    )
    static let syncSyncingSubtitle = String(
        localized: "settings.syncStatus.syncing.subtitle",
        defaultValue: "Changes are currently syncing with iCloud.",
        comment: "Status subtitle while changes are syncing with iCloud."
    )
    static let syncPreparingSubtitle = String(
        localized: "settings.syncStatus.preparing.subtitle",
        defaultValue: "The app is preparing the iCloud sync session for supported data.",
        comment: "Status subtitle while preparing iCloud sync."
    )
    static let syncImportingSubtitle = String(
        localized: "settings.syncStatus.importing.subtitle",
        defaultValue: "Changes from iCloud are currently being applied on this device.",
        comment: "Status subtitle while applying changes from iCloud."
    )
    static let syncUploadingSubtitle = String(
        localized: "settings.syncStatus.uploading.subtitle",
        defaultValue: "Changes from this device are currently being uploaded to iCloud.",
        comment: "Status subtitle while uploading changes to iCloud."
    )
    static let syncNoAccountSubtitle = String(
        localized: "settings.syncStatus.noAccount.subtitle",
        defaultValue: "Sign in to iCloud with the Apple ID used on this device to enable sync.",
        comment: "Status subtitle when iCloud sign-in is required."
    )
    static let syncRestrictedSubtitle = String(
        localized: "settings.syncStatus.restricted.subtitle",
        defaultValue: "This device cannot use iCloud right now because account changes or CloudKit access are restricted.",
        comment: "Status subtitle when iCloud access is restricted."
    )
    static let syncTemporarilyUnavailableSubtitle = String(
        localized: "settings.syncStatus.temporarilyUnavailable.subtitle",
        defaultValue: "The current iCloud account is temporarily unavailable. Try again later.",
        comment: "Status subtitle when iCloud account is temporarily unavailable."
    )
    static let syncCouldNotDetermineSubtitle = String(
        localized: "settings.syncStatus.couldNotDetermine.subtitle",
        defaultValue: "The app could not determine the current iCloud account status. Check the device Apple ID and iCloud availability, then try again.",
        comment: "Status subtitle when iCloud account status could not be determined."
    )
    static let bootstrapFallbackNoAccountReason = String(
        localized: "settings.syncStatus.fallback.noAccount.reason",
        defaultValue: "the device is not signed in to iCloud",
        comment: "Reason phrase used inside the iCloud sync local-only fallback preference subtitle."
    )
    static let bootstrapFallbackRestrictedReason = String(
        localized: "settings.syncStatus.fallback.restricted.reason",
        defaultValue: "iCloud access is currently restricted on this device",
        comment: "Reason phrase used inside the iCloud sync local-only fallback preference subtitle."
    )
    static let bootstrapFallbackTemporarilyUnavailableReason = String(
        localized: "settings.syncStatus.fallback.temporarilyUnavailable.reason",
        defaultValue: "the current iCloud account is temporarily unavailable",
        comment: "Reason phrase used inside the iCloud sync local-only fallback preference subtitle."
    )
    static let bootstrapFallbackCouldNotDetermineReason = String(
        localized: "settings.syncStatus.fallback.couldNotDetermine.reason",
        defaultValue: "iCloud availability could not be confirmed",
        comment: "Reason phrase used inside the iCloud sync local-only fallback preference subtitle."
    )
    static let bootstrapFallbackUnavailableReason = String(
        localized: "settings.syncStatus.fallback.unavailable.reason",
        defaultValue: "iCloud is not available for this launch",
        comment: "Fallback reason phrase used inside the iCloud sync local-only fallback preference subtitle."
    )
    static let clearArchivedArticlesAlertTitle = String(
        localized: "settings.alert.clearArchivedArticles.title",
        defaultValue: "Clear archived articles?",
        comment: "Confirmation alert title for clearing archived articles."
    )
    static let clearArchivedArticlesAlertAction = String(
        localized: "settings.alert.clearArchivedArticles.action",
        defaultValue: "Clear Articles",
        comment: "Destructive confirmation button title for clearing archived articles."
    )
    static let clearArchivedArticlesAlertMessage = String(
        localized: "settings.alert.clearArchivedArticles.message",
        defaultValue: "This removes archived articles from this device and iCloud. Starred articles, current articles, and saved article images are not affected.",
        comment: "Confirmation alert message for clearing archived articles."
    )
    static let clearArticleImageCacheAlertTitle = String(
        localized: "settings.alert.clearArticleImageCache.title",
        defaultValue: "Clear article image cache?",
        comment: "Confirmation alert title for clearing cached article images."
    )
    static let clearArticleImageCacheAlertMessage = String(
        localized: "settings.alert.clearArticleImageCache.message",
        defaultValue: "This removes article images saved on this device. Images can be downloaded again when articles are opened.",
        comment: "Confirmation alert message for clearing cached article images."
    )
    static let clearFeedIconCacheAlertTitle = String(
        localized: "settings.alert.clearFeedIconCache.title",
        defaultValue: "Clear feed icon cache?",
        comment: "Confirmation alert title for clearing cached feed icons."
    )
    static let clearFeedIconCacheAlertMessage = String(
        localized: "settings.alert.clearFeedIconCache.message",
        defaultValue: "This removes feed icons saved on this device. Icons can be discovered and downloaded again during refresh or when the sidebar is shown.",
        comment: "Confirmation alert message for clearing cached feed icons."
    )
    static let clearCacheAlertAction = String(
        localized: "settings.alert.clearCache.action",
        defaultValue: "Clear Cache",
        comment: "Destructive confirmation button title for clearing a cache."
    )
    static let cancelAction = CommonLocalization.cancelAction
    static let okAction = String(
        localized: "settings.alert.ok.action",
        defaultValue: "OK",
        comment: "Dismiss button title in settings status alerts."
    )
    static let importPreviewHeadline = String(
        localized: "settings.opmlImportPreview.headline",
        defaultValue: "Review feeds before import",
        comment: "Headline in the OPML import preview sheet."
    )
    static let importPreviewDescription = String(
        localized: "settings.opmlImportPreview.description",
        defaultValue: "App found feeds in the selected OPML file. Check the summary before adding them to your feed list.",
        comment: "Description in the OPML import preview sheet."
    )
    static let importPreviewSubscriptionsTitle = String(
        localized: "settings.opmlImportPreview.subscriptions.title",
        defaultValue: "Feeds",
        comment: "Summary row title for total feeds in OPML import preview."
    )
    static let importPreviewReadyTitle = String(
        localized: "settings.opmlImportPreview.ready.title",
        defaultValue: "Ready to Import",
        comment: "Summary row title for importable feeds in OPML import preview."
    )
    static let importPreviewSkippedTitle = String(
        localized: "settings.opmlImportPreview.skipped.title",
        defaultValue: "Will Be Skipped",
        comment: "Summary row title for skipped feeds in OPML import preview."
    )
    static let importPreviewNewFoldersTitle = String(
        localized: "settings.opmlImportPreview.newFolders.title",
        defaultValue: "New Folders",
        comment: "Summary row title for new folders in OPML import preview."
    )
    static let importPreviewFooter = String(
        localized: "settings.opmlImportPreview.footer",
        defaultValue: "Invalid and duplicate feeds are skipped automatically. Existing folders are reused; missing folders are created during import.",
        comment: "Footer in the OPML import preview sheet."
    )
    static let importPreviewNavigationTitle = String(
        localized: "settings.opmlImportPreview.navigationTitle",
        defaultValue: "Import OPML",
        comment: "Navigation title for the OPML import preview sheet."
    )
    static let importPreviewCloseAccessibilityLabel = String(
        localized: "settings.opmlImportPreview.accessibility.close",
        defaultValue: "Close Import Preview",
        comment: "Accessibility label for closing the OPML import preview sheet."
    )
    static let importPreviewImportAction = String(
        localized: "settings.opmlImportPreview.import.action",
        defaultValue: "Import",
        comment: "Confirmation button title in the OPML import preview sheet."
    )
    static let opmlStatusFallbackTitle = String(
        localized: "settings.opmlStatus.fallback.title",
        defaultValue: "OPML",
        comment: "Fallback title for OPML import/export status alerts."
    )
    static let feedsUnavailableMessage = String(
        localized: "settings.feedPortability.feedsUnavailable.message",
        defaultValue: "Feeds are unavailable in the current app environment.",
        comment: "Fallback error message when feed management services are unavailable."
    )
    static let importUnavailableTitle = String(
        localized: "settings.feedPortability.import.unavailable.title",
        defaultValue: "Import Unavailable",
        comment: "Status alert title when OPML import is unavailable."
    )
    static let opmlImportFailedTitle = String(
        localized: "settings.feedPortability.import.failed.title",
        defaultValue: "OPML Import Failed",
        comment: "Status alert title when OPML import fails."
    )
    static let opmlImportCompleteTitle = String(
        localized: "settings.feedPortability.import.complete.title",
        defaultValue: "OPML Import Complete",
        comment: "Status alert title when OPML import completes."
    )
    static func opmlImportCompleteMessage(createdFeedCount: Int, skippedEntryCount: Int) -> String {
        let messageFormat = String(localized:
            "settings.feedPortability.import.complete.message",
            defaultValue: "%1$@. %2$@.",
            comment: "Status alert message after OPML import completes. The first value is the localized imported feed count phrase; the second value is the localized skipped entry count phrase."
        )
        return CommonLocalization.localizedTemplate(
            messageFormat,
            opmlImportedFeedCount(createdFeedCount),
            opmlSkippedEntryCount(skippedEntryCount)
        )
    }
    private static func opmlImportedFeedCount(_ count: Int) -> String {
        let one = String(
            localized: "settings.feedPortability.import.complete.importedFeedCount.one",
            defaultValue: "%@ feed imported",
            comment: "Imported feed count phrase using the singular form. Placeholder is the localized imported feed count."
        )
        let few = String(
            localized: "settings.feedPortability.import.complete.importedFeedCount.few",
            defaultValue: "%@ feeds imported",
            comment: "Imported feed count phrase using the Russian few form. Placeholder is the localized imported feed count."
        )
        let many = String(
            localized: "settings.feedPortability.import.complete.importedFeedCount.many",
            defaultValue: "%@ feeds imported",
            comment: "Imported feed count phrase using the Russian many form. Placeholder is the localized imported feed count."
        )
        let other = String(
            localized: "settings.feedPortability.import.complete.importedFeedCount.other",
            defaultValue: "%@ feeds imported",
            comment: "Imported feed count phrase using the default plural form. Placeholder is the localized imported feed count."
        )
        return LocalizedPluralTemplates(
            one: one,
            few: few,
            many: many,
            other: other
        )
        .string(for: count)
    }
    private static func opmlSkippedEntryCount(_ count: Int) -> String {
        let one = String(
            localized: "settings.feedPortability.import.complete.skippedEntryCount.one",
            defaultValue: "%@ skipped",
            comment: "Skipped OPML entry count phrase using the singular form. Placeholder is the localized skipped entry count."
        )
        let few = String(
            localized: "settings.feedPortability.import.complete.skippedEntryCount.few",
            defaultValue: "%@ skipped",
            comment: "Skipped OPML entry count phrase using the Russian few form. Placeholder is the localized skipped entry count."
        )
        let many = String(
            localized: "settings.feedPortability.import.complete.skippedEntryCount.many",
            defaultValue: "%@ skipped",
            comment: "Skipped OPML entry count phrase using the Russian many form. Placeholder is the localized skipped entry count."
        )
        let other = String(
            localized: "settings.feedPortability.import.complete.skippedEntryCount.other",
            defaultValue: "%@ skipped",
            comment: "Skipped OPML entry count phrase using the default plural form. Placeholder is the localized skipped entry count."
        )
        return LocalizedPluralTemplates(
            one: one,
            few: few,
            many: many,
            other: other
        )
        .string(for: count)
    }
    static let opmlImportSaveFailureMessage = String(
        localized: "settings.feedPortability.import.saveFailure.message",
        defaultValue: "The app could not save the selected OPML feeds. Try again.",
        comment: "Status alert message when OPML import persistence fails."
    )
    static let selectedFileEmptyMessage = String(
        localized: "settings.feedPortability.import.emptyFile.message",
        defaultValue: "The selected file is empty.",
        comment: "Status alert message when the selected OPML file is empty."
    )
    static let selectedFileInvalidXMLMessage = String(
        localized: "settings.feedPortability.import.invalidXML.message",
        defaultValue: "The selected file is not valid XML.",
        comment: "Status alert message when the selected OPML file is not valid XML."
    )
    static let selectedFileNotOPMLMessage = String(
        localized: "settings.feedPortability.import.notOPML.message",
        defaultValue: "The selected file is not an OPML document.",
        comment: "Status alert message when the selected file is not an OPML document."
    )
    static let selectedOPMLMissingBodyMessage = String(
        localized: "settings.feedPortability.import.missingBody.message",
        defaultValue: "The selected OPML document does not contain a feed list.",
        comment: "Status alert message when OPML does not contain a feed list."
    )
    static let selectedOPMLReadFailureMessage = String(
        localized: "settings.feedPortability.import.readFailure.message",
        defaultValue: "The app could not read the selected OPML file.",
        comment: "Status alert message when OPML parsing fails for an unknown reason."
    )
    static let selectedFileReadFailureMessage = String(
        localized: "settings.feedPortability.import.selectedFileReadFailure.message",
        defaultValue: "The app could not read the selected file.",
        comment: "Status alert message when the imported file URL cannot be read."
    )
    static let selectedFileOpenFailureMessage = String(
        localized: "settings.feedPortability.import.selectedFileOpenFailure.message",
        defaultValue: "The selected file could not be opened.",
        comment: "Status alert message when the file importer cannot open the selected file."
    )
    static let exportUnavailableTitle = String(
        localized: "settings.feedPortability.export.unavailable.title",
        defaultValue: "Export Unavailable",
        comment: "Status alert title when OPML export is unavailable."
    )
    static let opmlExportFailedTitle = String(
        localized: "settings.feedPortability.export.failed.title",
        defaultValue: "OPML Export Failed",
        comment: "Status alert title when OPML export fails."
    )
    static let opmlExportCompleteTitle = String(
        localized: "settings.feedPortability.export.complete.title",
        defaultValue: "OPML Export Complete",
        comment: "Status alert title when OPML export completes."
    )
    static let opmlExportBuildFailureMessage = String(
        localized: "settings.feedPortability.export.buildFailure.message",
        defaultValue: "The app could not build an OPML file right now. Try again.",
        comment: "Status alert message when OPML export document generation fails."
    )
    static let opmlExportCompleteMessage = String(
        localized: "settings.feedPortability.export.complete.message",
        defaultValue: "Your feeds were exported successfully.",
        comment: "Status alert message when OPML export completes."
    )
    static let opmlExportSaveFailureMessage = String(
        localized: "settings.feedPortability.export.saveFailure.message",
        defaultValue: "The app could not save the OPML file. Try again.",
        comment: "Status alert message when writing the OPML export file fails."
    )
}
