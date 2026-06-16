import Foundation

enum ReadingLocalization {
    static let articlesTitle = String(
        localized: "reading.articles.navigation.title",
        defaultValue: "Articles",
        comment: "Default navigation title for the article list when no source-specific title is available."
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
    static let sourceFallbackTitle = String(
        localized: "reading.articles.sourceFallback.title",
        defaultValue: "Feed",
        comment: "Fallback title for a selected feed when the feed title is unavailable."
    )
    static let noUnreadItemsSubtitle = String(
        localized: "reading.articles.subtitle.noUnread",
        defaultValue: "No Unread Items",
        comment: "Article list subtitle when there are no unread articles."
    )
    static let unreadItemSubtitleOne = String(
        localized: "reading.articles.subtitle.unread.one",
        defaultValue: "1 Unread Item",
        comment: "Article list subtitle for exactly one unread article."
    )
    static let unreadItemSubtitleFormat = String(
        localized: "reading.articles.subtitle.unread.format",
        defaultValue: "%lld Unread Items",
        comment: "Article list subtitle for multiple unread articles. Placeholder is the unread article count."
    )
    static let starredItemSubtitleOne = String(
        localized: "reading.articles.subtitle.starred.one",
        defaultValue: "1 Starred Item",
        comment: "Article list subtitle for exactly one starred article."
    )
    static let starredItemSubtitleFormat = String(
        localized: "reading.articles.subtitle.starred.format",
        defaultValue: "%lld Starred Items",
        comment: "Article list subtitle for multiple starred articles. Placeholder is the starred article count."
    )
    static func unreadItemsSubtitle(count: Int) -> String {
        count == 1 ? unreadItemSubtitleOne : String.localizedStringWithFormat(unreadItemSubtitleFormat, count)
    }
    static func starredItemsSubtitle(count: Int) -> String {
        count == 1 ? starredItemSubtitleOne : String.localizedStringWithFormat(starredItemSubtitleFormat, count)
    }
    static let noSourceSelectedTitle = String(
        localized: "reading.articles.placeholder.noSource.title",
        defaultValue: "No Feed Selected",
        comment: "Article list placeholder title when no sidebar feed is selected."
    )
    static let noSourceSelectedDescription = String(
        localized: "reading.articles.placeholder.noSource.description",
        defaultValue: "Select All Items or a feed in the sidebar to load articles.",
        comment: "Article list placeholder description when no sidebar feed is selected."
    )
    static let noArticlesTitle = String(
        localized: "reading.articles.placeholder.empty.title",
        defaultValue: "No Articles",
        comment: "Article list placeholder title when the selected source has no articles."
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
    static let sourceEmptyDescription = String(
        localized: "reading.articles.placeholder.empty.source.description",
        defaultValue: "This feed has no articles for the active feeds filter.",
        comment: "Article list empty description for a feed."
    )
    static func folderEmptyDescription(folderName: String) -> String {
        String.localizedStringWithFormat(folderEmptyDescriptionFormat, folderName)
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
        String.localizedStringWithFormat(noSearchResultsDescriptionFormat, query)
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
    static let refreshRetryAction = String(
        localized: "reading.articles.refresh.retry.action",
        defaultValue: "Retry",
        comment: "Retry action title for article refresh failure banner."
    )
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
    static let singleSourceRefreshFailed = String(
        localized: "reading.articles.refresh.singleSource.failed",
        defaultValue: "The current feed failed to refresh.",
        comment: "Refresh failure message when one feed fails without a detailed error."
    )
    static let multipleSourcesRefreshFailedFormat = String(
        localized: "reading.articles.refresh.multipleSources.failed.format",
        defaultValue: "%lld feeds failed to refresh.",
        comment: "Refresh failure message when multiple feeds fail without a detailed error. Placeholder is failed feed count."
    )
    static let multipleSourcesRefreshFailedWithFirstErrorFormat = String(
        localized: "reading.articles.refresh.multipleSourcesWithFirstError.failed.format",
        defaultValue: "%1$lld feeds failed to refresh. First error: %2$@",
        comment: "Refresh failure message when multiple feeds fail. Placeholders are failed feed count and first error message."
    )
    static func multipleSourcesRefreshFailed(count: Int) -> String {
        String.localizedStringWithFormat(multipleSourcesRefreshFailedFormat, count)
    }
    static func multipleSourcesRefreshFailed(count: Int, firstError: String) -> String {
        String.localizedStringWithFormat(multipleSourcesRefreshFailedWithFirstErrorFormat, count, firstError)
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
    static let cancelAction = String(
        localized: "reading.action.cancel",
        defaultValue: "Cancel",
        comment: "Generic cancel action title in reading flow dialogs."
    )
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
