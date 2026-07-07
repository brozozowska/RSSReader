import SwiftUI
import UIKit

struct FeedIconView: View {
    @Environment(\.appDependencies) private var dependencies
    @Environment(AppState.self) private var appState
    @Environment(\.colorScheme) private var colorScheme
    let iconURL: String?
    @State private var iconImage: Image?

    var body: some View {
        let policy = FeedIconRenderingPolicy.sidebar(colorScheme: colorScheme)
        let containerShape = RoundedRectangle(cornerRadius: policy.cornerRadius, style: .continuous)

        ZStack {
            containerShape
                .fill(.secondary.opacity(policy.backgroundOpacity))

            iconContent(policy: policy)
        }
        .frame(width: policy.containerSize, height: policy.containerSize)
        .clipShape(containerShape)
        .overlay {
            containerShape
                .stroke(.secondary.opacity(policy.borderOpacity), lineWidth: policy.borderWidth)
        }
        .task(id: cacheOnlyLoadID) {
            await loadCachedIcon()
        }
        .onChange(of: appState.feedIconCacheResetID) { _, _ in
            iconImage = nil
        }
    }

    private var cacheOnlyLoadID: FeedIconCacheOnlyLoadID {
        FeedIconCacheOnlyLoadID(
            iconURL: iconURL,
            sidebarReloadID: appState.sidebarReloadID
        )
    }

    private var resolvedURL: URL? {
        guard let iconURL else { return nil }
        return URL(string: iconURL)
    }

    private func iconContent(policy: FeedIconRenderingPolicy) -> some View {
        Group {
            if let iconImage {
                iconImage
                    .resizable()
                    .scaledToFit()
            } else {
                placeholder
            }
        }
        .frame(width: policy.iconSize, height: policy.iconSize)
        .clipShape(RoundedRectangle(cornerRadius: policy.iconCornerRadius, style: .continuous))
    }

    private var placeholder: some View {
        Image(systemName: "newspaper")
            .font(.caption.weight(.medium))
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
    let iconURL: String?
    let sidebarReloadID: UUID
}
