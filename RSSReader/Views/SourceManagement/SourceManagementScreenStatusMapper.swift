import Foundation

enum SourceManagementScreenStatusMapper {
    static func createFolderErrorMessage(_ error: SourceManagementServiceError) -> String {
        switch error {
        case .emptyFolderName:
            return "Enter a folder name to continue."
        case .duplicateFolderName:
            return "A folder with this name already exists."
        case .invalidFeedURL,
                .feedDiscoveryFailed,
                .previewUnavailableForNotModifiedResponse,
                .duplicateFeed,
                .duplicateFeedDisplayName,
                .feedNotFound,
                .folderNotFound:
            return "Unable to create the folder right now. Try again."
        }
    }

    static func moveSourceErrorMessage(_ error: SourceManagementServiceError) -> String {
        switch error {
        case .feedNotFound:
            return "The selected source no longer exists. Reload the move flow and try again."
        case .folderNotFound:
            return "The selected folder no longer exists. Reload the move flow and choose another destination."
        case .invalidFeedURL,
                .feedDiscoveryFailed,
                .previewUnavailableForNotModifiedResponse,
                .duplicateFeed,
                .duplicateFeedDisplayName,
                .emptyFolderName,
                .duplicateFolderName:
            return "Unable to move the source right now. Try again."
        }
    }

    static func addFeedSaveUnavailableStatus(
        isEditing: Bool
    ) -> SourceManagementAddFeedStatusPresentation {
        SourceManagementAddFeedStatusPresentation(
            title: isEditing ? "Feed editing is unavailable" : "Feed creation is unavailable",
            kind: .failure,
            detail: isEditing
                ? "The app cannot save source changes in the current environment."
                : "The app cannot save a new source in the current environment."
        )
    }

    static func addFeedSaveFailureStatus(
        for error: SourceManagementServiceError,
        isEditing: Bool
    ) -> SourceManagementAddFeedStatusPresentation {
        switch error {
        case .duplicateFeed:
            return SourceManagementAddFeedStatusPresentation(
                title: "This feed is already in the library",
                kind: .warning,
                detail: isEditing
                    ? "Another source already uses this normalized URL. Change the feed URL and try again."
                    : "Another source with the same normalized URL was saved before this create step finished."
            )
        case .duplicateFeedDisplayName:
            return SourceManagementAddFeedStatusPresentation(
                title: "This display name is already in use",
                kind: .warning,
                detail: "Choose a different source name before saving."
            )
        case .folderNotFound:
            return SourceManagementAddFeedStatusPresentation(
                title: "Destination folder is unavailable",
                kind: .failure,
                detail: "The selected folder no longer exists. Choose another destination and try again."
            )
        case .invalidFeedURL,
                .feedDiscoveryFailed,
                .previewUnavailableForNotModifiedResponse,
                .emptyFolderName,
                .duplicateFolderName,
                .feedNotFound:
            return SourceManagementAddFeedStatusPresentation(
                title: isEditing ? "Feed changes could not be saved" : "Feed could not be added",
                kind: .failure,
                detail: isEditing
                    ? "Unable to save the source changes right now. Try again."
                    : "Unable to save the new source right now. Try again."
            )
        }
    }

    static func addFeedPreviewUnavailableStatus() -> SourceManagementAddFeedStatusPresentation {
        SourceManagementAddFeedStatusPresentation(
            title: "Source preview is unavailable",
            kind: .failure,
            detail: "The app cannot check this source right now."
        )
    }

    static func addFeedPreviewFailureStatus(
        for error: Error
    ) -> SourceManagementAddFeedStatusPresentation {
        if let error = error as? SourceManagementServiceError {
            return addFeedPreviewFailureStatus(for: error)
        }

        if let error = error as? FeedFetchError {
            return addFeedPreviewFailureStatus(for: error)
        }

        if let error = error as? FeedParserError {
            return addFeedPreviewFailureStatus(for: error)
        }

        return SourceManagementAddFeedStatusPresentation(
            title: "Preview could not be loaded",
            kind: .failure,
            detail: "Unable to check this source right now. Try again."
        )
    }

    static func addFeedPreviewFailureStatus(
        for error: SourceManagementServiceError
    ) -> SourceManagementAddFeedStatusPresentation {
        switch error {
        case .invalidFeedURL:
            return SourceManagementAddFeedStatusPresentation(
                title: "Enter a valid source address",
                kind: .failure,
                detail: "Use a website address or a direct RSS / Atom feed link."
            )
        case .feedDiscoveryFailed:
            return SourceManagementAddFeedStatusPresentation(
                title: "Feed was not found",
                kind: .failure,
                detail: "The app could not find a supported RSS or Atom feed for this address."
            )
        case .previewUnavailableForNotModifiedResponse:
            return SourceManagementAddFeedStatusPresentation(
                title: "Source could not be checked",
                kind: .failure,
                detail: "The source did not send enough information to review it right now."
            )
        case .duplicateFeed,
                .duplicateFeedDisplayName,
                .emptyFolderName,
                .duplicateFolderName,
                .feedNotFound,
                .folderNotFound:
            return SourceManagementAddFeedStatusPresentation(
                title: "Preview could not be loaded",
                kind: .failure,
                detail: "Unable to check this source right now. Try again."
            )
        }
    }

    static func addFeedPreviewFailureStatus(
        for error: FeedFetchError
    ) -> SourceManagementAddFeedStatusPresentation {
        switch error {
        case .transport(let transportError):
            return SourceManagementAddFeedStatusPresentation(
                title: "Network error while loading preview",
                kind: .failure,
                detail: networkFailureDetail(for: transportError)
            )
        case .invalidStatusCode(let statusCode):
            return SourceManagementAddFeedStatusPresentation(
                title: "Preview could not be loaded",
                kind: .failure,
                detail: "The server returned HTTP \(statusCode), so the app could not read this source."
            )
        case .unsupportedContentType(let contentType):
            let detail: String
            if let contentType, contentType.isEmpty == false {
                detail = "The address responded with \(contentType), not a supported RSS or Atom feed."
            } else {
                detail = "The address responded, but it does not look like a supported RSS or Atom feed."
            }
            return SourceManagementAddFeedStatusPresentation(
                title: "Source is not a supported feed",
                kind: .failure,
                detail: detail
            )
        }
    }

    static func addFeedPreviewFailureStatus(
        for error: FeedParserError
    ) -> SourceManagementAddFeedStatusPresentation {
        switch error {
        case .emptyDocument:
            return SourceManagementAddFeedStatusPresentation(
                title: "Source is not a supported feed",
                kind: .failure,
                detail: "The address responded, but there was no feed content to read."
            )
        case .malformedXML:
            return SourceManagementAddFeedStatusPresentation(
                title: "Source is not a supported feed",
                kind: .failure,
                detail: "The address responded, but the app could not read it as RSS or Atom."
            )
        case .unsupportedFeedKind:
            return SourceManagementAddFeedStatusPresentation(
                title: "Source is not a supported feed",
                kind: .failure,
                detail: "The address responded, but it did not contain a supported RSS or Atom feed."
            )
        case .missingRSSElement:
            return SourceManagementAddFeedStatusPresentation(
                title: "Source is not a supported feed",
                kind: .failure,
                detail: "The RSS feed is missing information the app needs before adding it."
            )
        case .missingAtomElement:
            return SourceManagementAddFeedStatusPresentation(
                title: "Source is not a supported feed",
                kind: .failure,
                detail: "The Atom feed is missing information the app needs before adding it."
            )
        }
    }

    static func networkFailureDetail(for error: FeedTransportError) -> String {
        switch error {
        case .timedOut:
            return "The request timed out before the feed preview could be loaded."
        case .cannotFindHost, .dnsLookupFailed:
            return "The host name could not be found for this source."
        case .cannotConnectToHost, .resourceUnavailable:
            return "The app could not connect to this source."
        case .networkConnectionLost:
            return "The network connection was lost while checking this source."
        case .notConnectedToInternet:
            return "Check the internet connection and try again."
        case .internationalRoamingOff, .callIsActive, .dataNotAllowed:
            return "The current network settings are blocking this request."
        case .invalidResponse:
            return "The server returned a response the app could not read."
        case .unknown:
            return "The source could not be checked for an unknown network reason."
        }
    }
}
