import SwiftUI
import UIKit

struct CachedArticleImageView: View {
    let url: URL
    @State private var phase: CachedArticleImagePhase

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
            .task(id: url) {
                await loadImage()
            }
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
                    accessibilityLabel: "Loading image"
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
                    Text("Image Unavailable")
                        .font(.subheadline.weight(.semibold))
                    Text("The article image could not be loaded.")
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
    private func loadImage() async {
        let memoryCache = ArticleImageMemoryCache.shared
        let diskCache = ArticleImageDiskCache.shared

        if let cachedImage = memoryCache.image(for: url) {
            phase = .success(cachedImage)
            return
        }

        phase = .loading

        do {
            if let cachedData = try? await diskCache.data(for: url),
               let diskImage = UIImage(data: cachedData) {
                memoryCache.insert(diskImage, for: url, cost: cachedData.count)
                phase = .success(diskImage)
                return
            }

            let (data, response) = try await URLSession.shared.data(from: url)
            try Task.checkCancellation()

            guard let httpResponse = response as? HTTPURLResponse,
                  (200...299).contains(httpResponse.statusCode),
                  let image = UIImage(data: data) else {
                phase = .failure
                return
            }

            try? await diskCache.insert(data, for: url)
            memoryCache.insert(image, for: url, cost: data.count)
            phase = .success(image)
        } catch is CancellationError {
            return
        } catch {
            phase = .failure
        }
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

@MainActor
final class ArticleImageMemoryCache {
    static let shared = ArticleImageMemoryCache()

    private let storage = NSCache<NSURL, UIImage>()
    private var storedURLs: Set<URL> = []

    init(countLimit: Int = 256, totalCostLimit: Int = 80 * 1024 * 1024) {
        storage.countLimit = countLimit
        storage.totalCostLimit = totalCostLimit
    }

    func image(for url: URL) -> UIImage? {
        guard let image = storage.object(forKey: url as NSURL) else {
            storedURLs.remove(url)
            return nil
        }

        return image
    }

    func insert(_ image: UIImage, for url: URL, cost: Int = 0) {
        storage.setObject(image, forKey: url as NSURL, cost: cost)
        storedURLs.insert(url)
    }

    var hasImages: Bool {
        storedURLs.isEmpty == false
    }

    func removeAllImages() {
        storage.removeAllObjects()
        storedURLs.removeAll()
    }
}
