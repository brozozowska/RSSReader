import SwiftUI
import UIKit

struct FeedIconView: View {
    @Environment(\.appDependencies) private var dependencies
    @Environment(AppState.self) private var appState
    let siteURL: String?
    let iconURL: String?
    @State private var iconImage: Image?

    var body: some View {
        Group {
            if let iconImage {
                iconImage
                    .resizable()
                    .scaledToFill()
            } else {
                placeholder
            }
        }
        .frame(width: 20, height: 20)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .task(id: cacheOnlyLoadID) {
            await loadCachedIcon()
        }
        .onChange(of: appState.feedIconCacheResetID) { _, _ in
            iconImage = nil
        }
    }

    private var cacheOnlyLoadID: FeedIconCacheOnlyLoadID {
        FeedIconCacheOnlyLoadID(
            siteURL: siteURL,
            iconURL: iconURL,
            sidebarReloadID: appState.sidebarReloadID
        )
    }

    private var resolvedURL: URL? {
        guard let iconURL else { return nil }
        return URL(string: iconURL)
    }

    private var placeholder: some View {
        Image(systemName: "newspaper")
            .font(.body.weight(.medium))
            .foregroundStyle(.secondary)
    }

    @MainActor
    private func loadCachedIcon() async {
        guard let resolvedURL else {
            iconImage = nil
            return
        }

        do {
            guard let data = try await dependencies.feedIconCache.cachedImageData(for: resolvedURL),
                  let uiImage = UIImage(data: data),
                  FeedIconImagePolicy.isSuitableIconSize(uiImage.size) else {
                iconImage = nil
                return
            }

            iconImage = Image(uiImage: uiImage)
        } catch {
            dependencies.logger.debug(
                "Failed to load cached feed icon for \(resolvedURL.absoluteString): \(String(describing: error))"
            )
            iconImage = nil
        }
    }
}

private struct FeedIconCacheOnlyLoadID: Hashable {
    let siteURL: String?
    let iconURL: String?
    let sidebarReloadID: UUID
}
