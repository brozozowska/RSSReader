import SwiftUI

struct ArticleListRefreshBanner: View {
    let isRefreshing: Bool
    let feedbackMessage: String?
    let retryAction: @MainActor () async -> Void
    let dismissAction: @MainActor () -> Void

    var body: some View {
        if isRefreshing {
            banner(
                title: "Refreshing Articles",
                message: "Updating the current selection.",
                showsRetryAction: false
            )
        } else if let feedbackMessage {
            banner(
                title: "Refresh Failed",
                message: feedbackMessage,
                showsRetryAction: true
            )
        }
    }

    private func banner(
        title: String,
        message: String,
        showsRetryAction: Bool
    ) -> some View {
        HStack(alignment: .center, spacing: 12) {
            if isRefreshing {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 12)

            if showsRetryAction {
                Button("Retry") {
                    Task {
                        await retryAction()
                    }
                }
                .font(.footnote.weight(.semibold))

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
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 4)
    }
}
