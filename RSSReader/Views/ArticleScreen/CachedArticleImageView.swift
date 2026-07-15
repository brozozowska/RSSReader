import SwiftUI
import UIKit

struct CachedArticleImageView: View {
    let url: URL
    @Environment(\.displayScale) private var displayScale
    @State private var phase: CachedArticleImagePhase
    @State private var displayWidth: CGFloat = 0

    @MainActor
    init(url: URL) {
        self.init(url: url, cache: ArticleImageMemoryCache.shared)
    }

    @MainActor
    init(url: URL, cache: ArticleImageMemoryCache) {
        self.url = url

        if let cachedImage = cache.image(for: url) {
            self._phase = State(initialValue: .success(cachedImage))
        } else {
            self._phase = State(initialValue: .empty)
        }
    }

    var body: some View {
        content
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                displayWidth = newWidth
            }
            .task(id: loadRequest) {
                guard let loadRequest else { return }
                await loadImage(displayTarget: loadRequest.displayTarget)
            }
    }

    private var loadRequest: CachedArticleImageLoadRequest? {
        guard displayWidth > 0, displayScale > 0 else { return nil }
        return CachedArticleImageLoadRequest(
            url: url,
            displayTarget: ArticleImageDisplayTarget(
                displayWidth: Double(displayWidth),
                displayScale: Double(displayScale)
            )
        )
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .empty, .loading:
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.quaternary.opacity(0.4))
                AppRefreshIndicator(
                    state: .refreshing,
                    size: 24,
                    lineWidth: 2.5,
                    tint: AnyShapeStyle(.secondary),
                    accessibilityLabel: ReadingLocalization.loadingImageAccessibilityLabel
                )
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
        case .success(let image):
            let layout = CachedArticleImageLayoutPolicy.layout(for: image.size)

            Image(uiImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: layout.maxImageWidth)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .frame(maxWidth: .infinity, alignment: layout.swiftUIAlignment)
        case .failure:
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: "photo")
                    .font(.title3)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 2) {
                    Text(ReadingLocalization.imageUnavailableTitle)
                        .font(.subheadline.weight(.semibold))
                    Text(ReadingLocalization.imageUnavailableDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    @MainActor
    private func loadImage(displayTarget: ArticleImageDisplayTarget) async {
        phase = .loading

        do {
            let image = try await ArticleImageLoader.shared.loadImage(
                from: url,
                displayTarget: displayTarget
            )
            phase = .success(image)
        } catch is CancellationError {
            return
        } catch {
            phase = .failure
        }
    }
}

private struct CachedArticleImageLoadRequest: Hashable {
    let url: URL
    let displayTarget: ArticleImageDisplayTarget
}

enum CachedArticleImagePhase {
    case empty
    case loading
    case success(UIImage)
    case failure
}

struct CachedArticleImageLayout: Equatable {
    let maxImageWidth: CGFloat?
    let horizontalAlignment: CachedArticleImageHorizontalAlignment

    var swiftUIAlignment: Alignment {
        switch horizontalAlignment {
        case .leading:
            .leading
        case .center:
            .center
        }
    }
}

enum CachedArticleImageHorizontalAlignment: Equatable {
    case leading
    case center
}

enum CachedArticleImageLayoutPolicy {
    static let smallImageMaximumWidth: CGFloat = 320

    static func layout(for imageSize: CGSize) -> CachedArticleImageLayout {
        guard imageSize.width > 0, imageSize.height > 0 else {
            return CachedArticleImageLayout(maxImageWidth: nil, horizontalAlignment: .center)
        }

        if imageSize.width <= smallImageMaximumWidth {
            return CachedArticleImageLayout(
                maxImageWidth: imageSize.width,
                horizontalAlignment: .center
            )
        }

        return CachedArticleImageLayout(
            maxImageWidth: nil,
            horizontalAlignment: .center
        )
    }
}
