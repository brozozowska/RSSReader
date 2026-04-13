import SwiftUI

struct ArticleListRefreshBanner: View {
    let state: ArticlesScreenRefreshBannerState?
    let retryAction: @MainActor () async -> Void
    let dismissAction: @MainActor () -> Void

    var body: some View {
        if let state {
            banner(
                state: state
            )
        }
    }

    private func banner(state: ArticlesScreenRefreshBannerState) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if state.showsActivityIndicator {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.subheadline.weight(.semibold))
                Text(state.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            if state.showsRetryAction {
                Button("Retry") {
                    Task {
                        await retryAction()
                    }
                }
                .font(.footnote.weight(.semibold))

                if state.showsDismissAction {
                    Button {
                        Task { @MainActor in
                            dismissAction()
                        }
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Dismiss refresh error")
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}
