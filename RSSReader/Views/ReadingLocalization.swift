import Foundation

enum ReadingLocalization {
    static let articlesTitle = String(
        localized: "reading.articles.navigation.title",
        defaultValue: "Articles",
        comment: "Default navigation title for the article list when no feed-specific title is available."
    )
    static let allItemsTitle = String(
        localized: "reading.articles.smartFilter.allItems.title",
        defaultValue: "All Items",
        comment: "Article list title for the all items smart filter."
    )
    static let unreadTitle = String(
        localized: "reading.articles.smartFilter.unread.title",
        defaultValue: "Unread",
        comment: "Article list title for the unread smart filter."
    )
    static let starredTitle = String(
        localized: "reading.articles.smartFilter.starred.title",
        defaultValue: "Starred",
        comment: "Article list title for the starred smart filter."
    )
    static let feedFallbackTitle = String(
        localized: "reading.articles.feedFallback.title",
        defaultValue: "Feed",
        comment: "Fallback title for a selected feed when the feed title is unavailable."
    )
    static let noUnreadItemsSubtitle = String(
        localized: "reading.articles.subtitle.noUnread",
        defaultValue: "No Unread Items",
        comment: "Article list subtitle when there are no unread articles."
    )
    static func unreadItemsSubtitle(count: Int) -> String {
        let template = String(
            localized: "reading.articles.subtitle.unread.count",
            defaultValue: "%lld Unread Items",
            comment: "Article list subtitle for an unread article count. Placeholder is the unread article count."
        )
        return CommonLocalization.localizedCountTemplate(template, count: count)
    }
    static func unreadItemsLowerBoundSubtitle(count: Int) -> String {
        lowerBoundSubtitle(unreadItemsSubtitle(count: count))
    }
    static func starredItemsSubtitle(count: Int) -> String {
        let template = String(
            localized: "reading.articles.subtitle.starred.count",
            defaultValue: "%lld Starred Items",
            comment: "Article list subtitle for a starred article count. Placeholder is the starred article count."
        )
        return CommonLocalization.localizedCountTemplate(template, count: count)
    }
    static func starredItemsLowerBoundSubtitle(count: Int) -> String {
        lowerBoundSubtitle(starredItemsSubtitle(count: count))
    }
    private static func lowerBoundSubtitle(_ exactCountSubtitle: String) -> String {
        let template = String(
            localized: "reading.articles.subtitle.loadedLowerBound.format",
            defaultValue: "≥ %@",
            comment: "Article list subtitle format indicating that the loaded count is a lower bound because more pages are available. Placeholder is a localized exact-count subtitle."
        )
        return CommonLocalization.localizedTemplate(template, exactCountSubtitle)
    }
    static let noSidebarSelectionTitle = String(
        localized: "reading.articles.placeholder.noSidebarSelection.title",
        defaultValue: "No Feed Selected",
        comment: "Article list placeholder title when no sidebar feed is selected."
    )
    static let noSidebarSelectionDescription = String(
        localized: "reading.articles.placeholder.noSidebarSelection.description",
        defaultValue: "Select All Items or a feed in the sidebar to load articles.",
        comment: "Article list placeholder description when no sidebar feed is selected."
    )
    static let noArticlesTitle = String(
        localized: "reading.articles.placeholder.empty.title",
        defaultValue: "No Articles",
        comment: "Article list placeholder title when the selected feed has no articles."
    )
    static let failedToLoadArticlesTitle = String(
        localized: "reading.articles.placeholder.failed.title",
        defaultValue: "Failed to Load Articles",
        comment: "Article list placeholder title when articles cannot be loaded."
    )
    static let unableToLoadArticlesTitle = String(
        localized: "reading.articles.placeholder.primaryFailed.title",
        defaultValue: "Unable to Load Articles",
        comment: "Primary article list failure title."
    )
    static let articleListQueryUnavailableMessage = String(
        localized: "reading.articles.error.queryUnavailable",
        defaultValue: "Article query service is unavailable.",
        comment: "Article list failure message when the query service is unavailable."
    )
    static let inboxEmptyDescription = String(
        localized: "reading.articles.placeholder.empty.inbox.description",
        defaultValue: "Your global inbox has no stored articles yet.",
        comment: "Article list empty description for the global inbox."
    )
    static let unreadEmptyDescription = String(
        localized: "reading.articles.placeholder.empty.unread.description",
        defaultValue: "There are no unread articles in your feeds.",
        comment: "Article list empty description for unread smart view."
    )
    static let starredEmptyDescription = String(
        localized: "reading.articles.placeholder.empty.starred.description",
        defaultValue: "You have not starred any articles yet.",
        comment: "Article list empty description for starred smart view."
    )
    static let folderEmptyDescriptionFormat = String(
        localized: "reading.articles.placeholder.empty.folder.description.format",
        defaultValue: "%@ has no articles for the active feeds filter.",
        comment: "Article list empty description for a folder. Placeholder is folder name."
    )
    static let feedEmptyDescription = String(
        localized: "reading.articles.placeholder.empty.feed.description",
        defaultValue: "This feed has no articles for the active feeds filter.",
        comment: "Article list empty description for a feed."
    )
    static func folderEmptyDescription(folderName: String) -> String {
        CommonLocalization.localizedTemplate(folderEmptyDescriptionFormat, folderName)
    }
    static let noSearchResultsTitle = String(
        localized: "reading.articles.search.empty.title",
        defaultValue: "No Search Results",
        comment: "Article list search placeholder title when no articles match the query."
    )
    static let noSearchResultsDescriptionFormat = String(
        localized: "reading.articles.search.empty.description.format",
        defaultValue: "No visible articles match \"%@\".",
        comment: "Article list search placeholder description. Placeholder is the search query."
    )
    static let searchPrompt = String(
        localized: "reading.articles.search.prompt",
        defaultValue: "Search Articles",
        comment: "Search field prompt for the article list."
    )
    static func noSearchResultsDescription(query: String) -> String {
        CommonLocalization.localizedTemplate(noSearchResultsDescriptionFormat, query)
    }
    static let loadingArticlesTitle = String(
        localized: "reading.articles.loading.title",
        defaultValue: "Loading Articles",
        comment: "Primary loading title for the article list."
    )
    static let refreshFailedTitle = String(
        localized: "reading.articles.refresh.failed.title",
        defaultValue: "Refresh Failed",
        comment: "Inline article list refresh failure title."
    )
    static let refreshRetryAction = CommonLocalization.retryAction
    static let dismissRefreshErrorAccessibilityLabel = String(
        localized: "reading.articles.refresh.dismiss.accessibility",
        defaultValue: "Dismiss refresh error",
        comment: "Accessibility label for dismissing article refresh error banner."
    )
    static let refreshCurrentSelectionFailed = String(
        localized: "reading.articles.refresh.currentSelection.failed",
        defaultValue: "Unable to refresh the current selection right now.",
        comment: "Refresh failure message when the current article selection cannot be refreshed."
    )
    static let singleFeedRefreshFailed = String(
        localized: "reading.articles.refresh.singleFeed.failed",
        defaultValue: "The current feed failed to refresh.",
        comment: "Refresh failure message when one feed fails without a detailed error."
    )
    static func multipleFeedsRefreshFailed(count: Int) -> String {
        let template = String(
            localized: "reading.articles.refresh.multipleFeeds.failed.count",
            defaultValue: "%lld feeds failed to refresh.",
            comment: "Refresh failure message when feeds fail without a detailed error. Placeholder is the failed feed count."
        )
        return CommonLocalization.localizedCountTemplate(template, count: count)
    }
    static func multipleFeedsRefreshFailed(count: Int, firstError: String) -> String {
        let template = String(
            localized: "reading.articles.refresh.multipleFeedsWithFirstError.failed.count",
            defaultValue: "%lld feeds failed to refresh. First error: %@",
            comment: "Refresh failure message when feeds fail with a first error. Placeholders are the failed feed count and first error message."
        )
        return String.localizedStringWithFormat(template, Int64(count), firstError)
    }
    static let markAllAsReadAccessibilityLabel = String(
        localized: "reading.articles.markAllRead.accessibility",
        defaultValue: "Mark all as read",
        comment: "Accessibility label for the mark all visible articles as read toolbar action."
    )
    static let markAllAsReadDialogTitle = String(
        localized: "reading.articles.markAllRead.dialog.title",
        defaultValue: "Mark all as read?",
        comment: "Confirmation dialog title for marking all visible articles as read."
    )
    static let markAllAsReadDialogAction = String(
        localized: "reading.articles.markAllRead.dialog.confirm",
        defaultValue: "Mark all as read",
        comment: "Destructive confirmation action title for marking all visible articles as read."
    )
    static let cancelAction = CommonLocalization.cancelAction
    static let markAllAsReadDialogMessage = String(
        localized: "reading.articles.markAllRead.dialog.message",
        defaultValue: "This action will mark all visible articles as read.",
        comment: "Confirmation dialog message for marking all visible articles as read."
    )
    static let todaySectionTitle = String(
        localized: "reading.articles.section.today",
        defaultValue: "Today",
        comment: "Article list date section title for today."
    )
    static let yesterdaySectionTitle = String(
        localized: "reading.articles.section.yesterday",
        defaultValue: "Yesterday",
        comment: "Article list date section title for yesterday."
    )
    static let noArticleSelectedTitle = String(
        localized: "reading.article.placeholder.noSelection.title",
        defaultValue: "No Article Selected",
        comment: "Article reader placeholder title when no article is selected."
    )
    static let articleNotFoundTitle = String(
        localized: "reading.article.placeholder.notFound.title",
        defaultValue: "Article Not Found",
        comment: "Article reader placeholder title when selected article cannot be found."
    )
    static let articleNotFoundDescription = String(
        localized: "reading.article.placeholder.notFound.description",
        defaultValue: "The selected article could not be loaded from persistence.",
        comment: "Article reader placeholder description when selected article cannot be found."
    )
    static let failedToLoadArticleTitle = String(
        localized: "reading.article.placeholder.failed.title",
        defaultValue: "Failed to Load Article",
        comment: "Article reader placeholder title when article loading fails."
    )
    static let articleQueryUnavailableMessage = String(
        localized: "reading.article.error.queryUnavailable",
        defaultValue: "Article query service is unavailable.",
        comment: "Article reader failure message when the query service is unavailable."
    )
    static let loadingArticleTitle = String(
        localized: "reading.article.loading.title",
        defaultValue: "Loading Article",
        comment: "Primary loading title for the article reader."
    )
    static let untitledArticleTitle = String(
        localized: "reading.article.untitled.title",
        defaultValue: "Untitled Article",
        comment: "Fallback article title when the feed item has no title."
    )
    static let markReadAction = String(
        localized: "reading.article.action.markRead",
        defaultValue: "Mark Read",
        comment: "Action title for marking an article as read."
    )
    static let markUnreadAction = String(
        localized: "reading.article.action.markUnread",
        defaultValue: "Mark Unread",
        comment: "Action title for marking an article as unread."
    )
    static let starAction = String(
        localized: "reading.article.action.star",
        defaultValue: "Star",
        comment: "Action title for starring an article."
    )
    static let unstarAction = String(
        localized: "reading.article.action.unstar",
        defaultValue: "Unstar",
        comment: "Action title for unstarring an article."
    )
    static let readAction = String(
        localized: "reading.articles.row.action.read",
        defaultValue: "Read",
        comment: "Swipe action title for marking an article row as read."
    )
    static let unreadAction = String(
        localized: "reading.articles.row.action.unread",
        defaultValue: "Unread",
        comment: "Swipe action title for marking an article row as unread."
    )
    static let openSourceArticleAction = String(
        localized: "reading.article.action.openSource",
        defaultValue: "Open Source Article",
        comment: "Action title for opening the source article in a browser."
    )
    static let openOriginalArticleAccessibilityLabel = String(
        localized: "reading.article.openOriginal.accessibility",
        defaultValue: "Open Original Article",
        comment: "Accessibility label for tapping the article title to open the original source article."
    )
    static let shareActionAccessibilityLabel = String(
        localized: "reading.article.share.accessibility",
        defaultValue: "Share",
        comment: "Accessibility label for the article share action."
    )
    static let nextArticleAccessibilityLabel = String(
        localized: "reading.article.next.accessibility",
        defaultValue: "Next Article",
        comment: "Accessibility label for navigating to the next article."
    )
    static let previousArticleAccessibilityLabel = String(
        localized: "reading.article.previous.accessibility",
        defaultValue: "Previous Article",
        comment: "Accessibility label for navigating to the previous article."
    )
    static let summaryOnlyFallbackNotice = String(
        localized: "reading.article.body.summaryOnly.notice",
        defaultValue: "This article included only a summary in the received feed.",
        comment: "Reader body notice when the feed contains only an article summary."
    )
    static let emptyBodyFallbackNotice = String(
        localized: "reading.article.body.empty.notice",
        defaultValue: "This article did not include body content in the received feed.",
        comment: "Reader body notice when the feed contains no article body."
    )
    static let openEmbeddedContentAction = String(
        localized: "reading.article.media.openEmbedded",
        defaultValue: "Open embedded content",
        comment: "Media fallback action title for embedded article content."
    )
    static let openVideoAction = String(
        localized: "reading.article.media.openVideo",
        defaultValue: "Open video",
        comment: "Media fallback action title for video content."
    )
    static let openAudioAction = String(
        localized: "reading.article.media.openAudio",
        defaultValue: "Open audio",
        comment: "Media fallback action title for audio content."
    )
    static let openMediaAction = String(
        localized: "reading.article.media.openGeneric",
        defaultValue: "Open media",
        comment: "Media fallback action title for generic unsupported media."
    )
    static let loadingImageAccessibilityLabel = String(
        localized: "reading.article.image.loading.accessibility",
        defaultValue: "Loading image",
        comment: "Accessibility label for article image loading indicator."
    )
    static let imageUnavailableTitle = String(
        localized: "reading.article.image.unavailable.title",
        defaultValue: "Image Unavailable",
        comment: "Article image fallback title when the image cannot load."
    )
    static let imageUnavailableDescription = String(
        localized: "reading.article.image.unavailable.description",
        defaultValue: "The article image could not be loaded.",
        comment: "Article image fallback description when the image cannot load."
    )

    static let cannotOpenLinkTitle = String(
        localized: "reading.safari.unsupported.title",
        defaultValue: "Cannot Open Link",
        comment: "Safari fallback title when the article link cannot be opened."
    )
    static let cannotOpenLinkDescription = String(
        localized: "reading.safari.unsupported.description",
        defaultValue: "This article link can't be opened in the in-app browser.",
        comment: "Safari fallback description when the article link cannot be opened."
    )
    static let closeAction = String(
        localized: "reading.action.close",
        defaultValue: "Close",
        comment: "Generic close action title in reading flow."
    )
}
