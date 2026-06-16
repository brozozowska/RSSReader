import Foundation

enum FeedManagementScreenStatusMapper {
    static func createFolderErrorMessage(_ error: FeedManagementServiceError) -> String {
        switch error {
        case .emptyFolderName:
            return FeedManagementLocalization.enterFolderNameValidation
        case .duplicateFolderName:
            return FeedManagementLocalization.duplicateFolderNameValidation
        case .invalidFeedURL,
                .feedDiscoveryFailed,
                .previewUnavailableForNotModifiedResponse,
                .duplicateFeed,
                .duplicateFeedDisplayName,
                .feedNotFound,
                .folderNotFound:
            return String(localized: "feedManagement.createFolder.error.generic", defaultValue: "Unable to create the folder right now. Try again.", comment: "Generic create folder error message.")
        }
    }

    static func moveFeedErrorMessage(_ error: FeedManagementServiceError) -> String {
        switch error {
        case .feedNotFound:
            return String(localized: "feedManagement.moveFeed.error.feedNotFound", defaultValue: "The selected feed no longer exists. Reload the move flow and try again.", comment: "Move feed error when the selected feed no longer exists.")
        case .folderNotFound:
            return String(localized: "feedManagement.moveFeed.error.folderNotFound", defaultValue: "The selected folder no longer exists. Reload the move flow and choose another destination.", comment: "Move feed error when the selected folder no longer exists.")
        case .invalidFeedURL,
                .feedDiscoveryFailed,
                .previewUnavailableForNotModifiedResponse,
                .duplicateFeed,
                .duplicateFeedDisplayName,
                .emptyFolderName,
                .duplicateFolderName:
            return FeedManagementLocalization.feedMoveGenericFailure
        }
    }

    static func addFeedSaveUnavailableStatus(
        isEditing: Bool
    ) -> FeedManagementAddFeedStatusPresentation {
        FeedManagementAddFeedStatusPresentation(
            title: isEditing
                ? String(localized: "feedManagement.addFeed.saveUnavailable.edit.title", defaultValue: "Feed editing is unavailable", comment: "Failure title when feed editing service is unavailable.")
                : String(localized: "feedManagement.addFeed.saveUnavailable.add.title", defaultValue: "Feed creation is unavailable", comment: "Failure title when feed creation service is unavailable."),
            kind: .failure,
            detail: isEditing
                ? String(localized: "feedManagement.addFeed.saveUnavailable.edit.detail", defaultValue: "The app cannot save feed changes in the current environment.", comment: "Failure detail when feed editing service is unavailable.")
                : String(localized: "feedManagement.addFeed.saveUnavailable.add.detail", defaultValue: "The app cannot save a new feed in the current environment.", comment: "Failure detail when feed creation service is unavailable.")
        )
    }

    static func addFeedSaveFailureStatus(
        for error: FeedManagementServiceError,
        isEditing: Bool
    ) -> FeedManagementAddFeedStatusPresentation {
        switch error {
        case .duplicateFeed:
            return FeedManagementAddFeedStatusPresentation(
                title: FeedManagementLocalization.duplicateFeedTitle,
                kind: .warning,
                detail: isEditing
                    ? String(localized: "feedManagement.addFeed.save.duplicate.edit.detail", defaultValue: "Another feed already uses this normalized URL. Change the feed URL and try again.", comment: "Duplicate feed detail while editing a feed.")
                    : String(localized: "feedManagement.addFeed.save.duplicate.add.detail", defaultValue: "Another feed with the same normalized URL was saved before this create step finished.", comment: "Duplicate feed detail while adding a feed.")
            )
        case .duplicateFeedDisplayName:
            return FeedManagementAddFeedStatusPresentation(
                title: String(localized: "feedManagement.addFeed.save.duplicateDisplayName.title", defaultValue: "This display name is already in use", comment: "Warning title for duplicate feed display name."),
                kind: .warning,
                detail: String(localized: "feedManagement.addFeed.save.duplicateDisplayName.detail", defaultValue: "Choose a different feed name before saving.", comment: "Warning detail for duplicate feed display name.")
            )
        case .folderNotFound:
            return FeedManagementAddFeedStatusPresentation(
                title: String(localized: "feedManagement.addFeed.save.folderUnavailable.title", defaultValue: "Destination folder is unavailable", comment: "Failure title when selected destination folder no longer exists."),
                kind: .failure,
                detail: String(localized: "feedManagement.addFeed.save.folderUnavailable.detail", defaultValue: "The selected folder no longer exists. Choose another destination and try again.", comment: "Failure detail when selected destination folder no longer exists.")
            )
        case .invalidFeedURL,
                .feedDiscoveryFailed,
                .previewUnavailableForNotModifiedResponse,
                .emptyFolderName,
                .duplicateFolderName,
                .feedNotFound:
            return FeedManagementAddFeedStatusPresentation(
                title: isEditing
                    ? String(localized: "feedManagement.addFeed.save.editFailed.title", defaultValue: "Feed changes could not be saved", comment: "Generic failure title after feed edit save fails.")
                    : String(localized: "feedManagement.addFeed.save.addFailed.title", defaultValue: "Feed could not be added", comment: "Generic failure title after feed create save fails."),
                kind: .failure,
                detail: isEditing
                    ? String(localized: "feedManagement.addFeed.save.editFailed.detail", defaultValue: "Unable to save the feed changes right now. Try again.", comment: "Generic failure detail after feed edit save fails.")
                    : String(localized: "feedManagement.addFeed.save.addFailed.detail", defaultValue: "Unable to save the new feed right now. Try again.", comment: "Generic failure detail after feed create save fails.")
            )
        }
    }

    static func addFeedPreviewUnavailableStatus() -> FeedManagementAddFeedStatusPresentation {
        FeedManagementAddFeedStatusPresentation(
            title: String(localized: "feedManagement.addFeed.previewUnavailable.title", defaultValue: "Feed preview is unavailable", comment: "Failure title when feed preview service is unavailable."),
            kind: .failure,
            detail: String(localized: "feedManagement.addFeed.previewUnavailable.detail", defaultValue: "The app cannot check this feed right now.", comment: "Failure detail when feed preview service is unavailable.")
        )
    }

    static func addFeedPreviewFailureStatus(
        for error: Error
    ) -> FeedManagementAddFeedStatusPresentation {
        if let error = error as? FeedManagementServiceError {
            return addFeedPreviewFailureStatus(for: error)
        }

        if let error = error as? FeedFetchError {
            return addFeedPreviewFailureStatus(for: error)
        }

        if let error = error as? FeedParserError {
            return addFeedPreviewFailureStatus(for: error)
        }

        return FeedManagementAddFeedStatusPresentation(
            title: String(localized: "feedManagement.addFeed.preview.genericFailure.title", defaultValue: "Preview could not be loaded", comment: "Generic failure title when feed preview fails."),
            kind: .failure,
            detail: String(localized: "feedManagement.addFeed.preview.genericFailure.detail", defaultValue: "Unable to check this feed right now. Try again.", comment: "Generic failure detail when feed preview fails.")
        )
    }

    static func addFeedPreviewFailureStatus(
        for error: FeedManagementServiceError
    ) -> FeedManagementAddFeedStatusPresentation {
        switch error {
        case .invalidFeedURL:
            return FeedManagementAddFeedStatusPresentation(
                title: String(localized: "feedManagement.addFeed.preview.invalidURL.title", defaultValue: "Enter a valid feed address", comment: "Failure title for invalid feed preview URL."),
                kind: .failure,
                detail: FeedManagementLocalization.feedURLFooter
            )
        case .feedDiscoveryFailed:
            return FeedManagementAddFeedStatusPresentation(
                title: String(localized: "feedManagement.addFeed.preview.feedNotFound.title", defaultValue: "Feed was not found", comment: "Failure title when feed discovery fails."),
                kind: .failure,
                detail: String(localized: "feedManagement.addFeed.preview.feedNotFound.detail", defaultValue: "The app could not find a supported RSS or Atom feed for this address.", comment: "Failure detail when feed discovery fails.")
            )
        case .previewUnavailableForNotModifiedResponse:
            return FeedManagementAddFeedStatusPresentation(
                title: String(localized: "feedManagement.addFeed.preview.notModified.title", defaultValue: "Feed could not be checked", comment: "Failure title when feed preview cannot use not-modified response."),
                kind: .failure,
                detail: String(localized: "feedManagement.addFeed.preview.notModified.detail", defaultValue: "The feed did not send enough information to review it right now.", comment: "Failure detail when feed preview cannot use not-modified response.")
            )
        case .duplicateFeed,
                .duplicateFeedDisplayName,
                .emptyFolderName,
                .duplicateFolderName,
                .feedNotFound,
                .folderNotFound:
            return FeedManagementAddFeedStatusPresentation(
                title: String(localized: "feedManagement.addFeed.preview.genericFailure.title", defaultValue: "Preview could not be loaded", comment: "Generic failure title when feed preview fails."),
                kind: .failure,
                detail: String(localized: "feedManagement.addFeed.preview.genericFailure.detail", defaultValue: "Unable to check this feed right now. Try again.", comment: "Generic failure detail when feed preview fails.")
            )
        }
    }

    static func addFeedPreviewFailureStatus(
        for error: FeedFetchError
    ) -> FeedManagementAddFeedStatusPresentation {
        switch error {
        case .transport(let transportError):
            return FeedManagementAddFeedStatusPresentation(
                title: String(localized: "feedManagement.addFeed.preview.network.title", defaultValue: "Network error while loading preview", comment: "Failure title for network error while loading feed preview."),
                kind: .failure,
                detail: networkFailureDetail(for: transportError)
            )
        case .invalidStatusCode(let statusCode):
            return FeedManagementAddFeedStatusPresentation(
                title: String(localized: "feedManagement.addFeed.preview.genericFailure.title", defaultValue: "Preview could not be loaded", comment: "Generic failure title when feed preview fails."),
                kind: .failure,
                detail: String.localizedStringWithFormat(
                    String(localized: "feedManagement.addFeed.preview.httpStatus.detail.format", defaultValue: "The server returned HTTP %lld, so the app could not read this feed.", comment: "Feed preview failure detail for HTTP status. Placeholder is HTTP status code."),
                    statusCode
                )
            )
        case .unsupportedContentType(let contentType):
            let detail: String
            if let contentType, contentType.isEmpty == false {
                detail = String.localizedStringWithFormat(
                    String(localized: "feedManagement.addFeed.preview.unsupportedContentType.detail.format", defaultValue: "The address responded with %@, not a supported RSS or Atom feed.", comment: "Feed preview failure detail for unsupported content type. Placeholder is content type."),
                    contentType
                )
            } else {
                detail = String(localized: "feedManagement.addFeed.preview.unsupportedContentType.empty.detail", defaultValue: "The address responded, but it does not look like a supported RSS or Atom feed.", comment: "Feed preview failure detail for missing unsupported content type.")
            }
            return FeedManagementAddFeedStatusPresentation(
                title: String(localized: "feedManagement.addFeed.preview.unsupportedFeed.title", defaultValue: "This is not a supported feed", comment: "Failure title for unsupported feed."),
                kind: .failure,
                detail: detail
            )
        }
    }

    static func addFeedPreviewFailureStatus(
        for error: FeedParserError
    ) -> FeedManagementAddFeedStatusPresentation {
        switch error {
        case .emptyDocument:
            return FeedManagementAddFeedStatusPresentation(
                title: String(localized: "feedManagement.addFeed.preview.unsupportedFeed.title", defaultValue: "This is not a supported feed", comment: "Failure title for unsupported feed."),
                kind: .failure,
                detail: String(localized: "feedManagement.addFeed.preview.emptyDocument.detail", defaultValue: "The address responded, but there was no feed content to read.", comment: "Feed preview failure detail for empty feed document.")
            )
        case .malformedXML:
            return FeedManagementAddFeedStatusPresentation(
                title: String(localized: "feedManagement.addFeed.preview.unsupportedFeed.title", defaultValue: "This is not a supported feed", comment: "Failure title for unsupported feed."),
                kind: .failure,
                detail: String(localized: "feedManagement.addFeed.preview.malformedXML.detail", defaultValue: "The address responded, but the app could not read it as RSS or Atom.", comment: "Feed preview failure detail for malformed XML.")
            )
        case .unsupportedFeedKind:
            return FeedManagementAddFeedStatusPresentation(
                title: String(localized: "feedManagement.addFeed.preview.unsupportedFeed.title", defaultValue: "This is not a supported feed", comment: "Failure title for unsupported feed."),
                kind: .failure,
                detail: String(localized: "feedManagement.addFeed.preview.unsupportedFeedKind.detail", defaultValue: "The address responded, but it did not contain a supported RSS or Atom feed.", comment: "Feed preview failure detail for unsupported feed kind.")
            )
        case .missingRSSElement:
            return FeedManagementAddFeedStatusPresentation(
                title: String(localized: "feedManagement.addFeed.preview.unsupportedFeed.title", defaultValue: "This is not a supported feed", comment: "Failure title for unsupported feed."),
                kind: .failure,
                detail: String(localized: "feedManagement.addFeed.preview.missingRSS.detail", defaultValue: "The RSS feed is missing information the app needs before adding it.", comment: "Feed preview failure detail for missing RSS element.")
            )
        case .missingAtomElement:
            return FeedManagementAddFeedStatusPresentation(
                title: String(localized: "feedManagement.addFeed.preview.unsupportedFeed.title", defaultValue: "This is not a supported feed", comment: "Failure title for unsupported feed."),
                kind: .failure,
                detail: String(localized: "feedManagement.addFeed.preview.missingAtom.detail", defaultValue: "The Atom feed is missing information the app needs before adding it.", comment: "Feed preview failure detail for missing Atom element.")
            )
        }
    }

    static func networkFailureDetail(for error: FeedTransportError) -> String {
        switch error {
        case .timedOut:
            return String(localized: "feedManagement.addFeed.preview.network.timedOut", defaultValue: "The request timed out before the feed preview could be loaded.", comment: "Network failure detail for timeout.")
        case .cannotFindHost, .dnsLookupFailed:
            return String(localized: "feedManagement.addFeed.preview.network.hostNotFound", defaultValue: "The host name could not be found for this feed.", comment: "Network failure detail for host lookup failure.")
        case .cannotConnectToHost, .resourceUnavailable:
            return String(localized: "feedManagement.addFeed.preview.network.cannotConnect", defaultValue: "The app could not connect to this feed.", comment: "Network failure detail for connection failure.")
        case .networkConnectionLost:
            return String(localized: "feedManagement.addFeed.preview.network.connectionLost", defaultValue: "The network connection was lost while checking this feed.", comment: "Network failure detail for lost connection.")
        case .notConnectedToInternet:
            return String(localized: "feedManagement.addFeed.preview.network.offline", defaultValue: "Check the internet connection and try again.", comment: "Network failure detail for offline state.")
        case .internationalRoamingOff, .callIsActive, .dataNotAllowed:
            return String(localized: "feedManagement.addFeed.preview.network.blocked", defaultValue: "The current network settings are blocking this request.", comment: "Network failure detail for blocked network settings.")
        case .invalidResponse:
            return String(localized: "feedManagement.addFeed.preview.network.invalidResponse", defaultValue: "The server returned a response the app could not read.", comment: "Network failure detail for invalid response.")
        case .unknown:
            return String(localized: "feedManagement.addFeed.preview.network.unknown", defaultValue: "The feed could not be checked for an unknown network reason.", comment: "Network failure detail for unknown network failure.")
        }
    }
}
