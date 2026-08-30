import SwiftUI
import UIKit

struct CachedArticleImageView: View {
    let url: URL
    @Environment(\.displayScale) private var displayScale
    @State private var lifecycle: CachedArticleImageLoadLifecycle
    @State private var displayWidth: CGFloat = 0
    @State private var retryGeneration = 0

    @MainActor
    init(url: URL) {
        self.init(url: url, cache: ArticleImageMemoryCache.shared)
    }

    @MainActor
    init(url: URL, cache: ArticleImageMemoryCache) {
        self.url = url

        if let cachedImage = cache.image(for: url) {
            self._lifecycle = State(
                initialValue: CachedArticleImageLoadLifecycle(initialPhase: .success(cachedImage))
            )
        } else {
            self._lifecycle = State(
                initialValue: CachedArticleImageLoadLifecycle(initialPhase: .empty)
            )
        }
    }

    var body: some View {
        content
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { newWidth in
                displayWidth = newWidth
            }
            .task(id: loadTaskID) {
                guard let loadRequest else { return }
                await loadImage(loadRequest)
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

    private var loadTaskID: CachedArticleImageLoadTaskID? {
        loadRequest.map {
            CachedArticleImageLoadTaskID(request: $0, retryGeneration: retryGeneration)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch lifecycle.phase {
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
            Button {
                retryGeneration &+= 1
            } label: {
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

                    Spacer(minLength: 8)

                    Label(CommonLocalization.retryAction, systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.25), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .accessibilityHint(CommonLocalization.retryAction)
        }
    }

    @MainActor
    private func loadImage(_ request: CachedArticleImageLoadRequest) async {
        let token = lifecycle.begin(request)

        do {
            let image = try await ArticleImageLoader.shared.loadImage(
                from: request.url,
                displayTarget: request.displayTarget
            )
            if Task.isCancelled {
                lifecycle.cancel(token)
            } else {
                lifecycle.succeed(with: image, token: token)
            }
        } catch is CancellationError {
            lifecycle.cancel(token)
        } catch {
            if Task.isCancelled {
                lifecycle.cancel(token)
            } else {
                lifecycle.fail(token)
            }
        }
    }
}

struct CachedArticleImageLoadRequest: Hashable {
    let url: URL
    let displayTarget: ArticleImageDisplayTarget
}

private struct CachedArticleImageLoadTaskID: Hashable {
    let request: CachedArticleImageLoadRequest
    let retryGeneration: Int
}

struct CachedArticleImageLoadToken: Equatable {
    fileprivate let generation: Int
    let request: CachedArticleImageLoadRequest
}

struct CachedArticleImageLoadLifecycle {
    private(set) var phase: CachedArticleImagePhase
    private var generation = 0
    private var activeToken: CachedArticleImageLoadToken?

    init(initialPhase: CachedArticleImagePhase) {
        phase = initialPhase
    }

    mutating func begin(_ request: CachedArticleImageLoadRequest) -> CachedArticleImageLoadToken {
        generation &+= 1
        let token = CachedArticleImageLoadToken(generation: generation, request: request)
        activeToken = token
        phase = .loading
        return token
    }

    mutating func succeed(with image: UIImage, token: CachedArticleImageLoadToken) {
        guard activeToken == token else { return }
        activeToken = nil
        phase = .success(image)
    }

    mutating func fail(_ token: CachedArticleImageLoadToken) {
        guard activeToken == token else { return }
        activeToken = nil
        phase = .failure
    }

    mutating func cancel(_ token: CachedArticleImageLoadToken) {
        guard activeToken == token else { return }
        activeToken = nil
        phase = .empty
    }
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
