import SwiftUI

struct FeedManagementCloseButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

struct FeedManagementScreenItemCard: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    let item: FeedManagementScreenItemPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10)
                    .fill(appThemeVariant.secondaryBackground)
                    .frame(width: 40, height: 40)

                Image(systemName: item.systemImageName)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)
            }

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Text(item.title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.primary)
                }

                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
    }
}
struct FeedManagementFolderPlacementRow: View {
    let option: FeedManagementFolderPlacementOptionPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: option.isSelected ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(option.isSelected ? Color.accentColor : .secondary)

            VStack(alignment: .leading, spacing: 4) {
                Text(option.title)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.primary)

                if let subtitle = option.subtitle {
                    Text(subtitle)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let trailingValue = option.trailingValue {
                Text(trailingValue)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
struct FeedManagementFeedbackCard: View {
    let feedback: FeedManagementFeedbackCardPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: feedback.tone.systemImageName)
                .foregroundStyle(feedback.tone.color)

            VStack(alignment: .leading, spacing: 4) {
                Text(feedback.title)
                    .font(.body.weight(.semibold))

                if let detail = feedback.detail {
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct FeedManagementFeedbackCardPresentation {
    let title: String
    let detail: String?
    let tone: FeedManagementFeedbackTone

    init(status: FeedManagementAddFeedStatusPresentation) {
        self.title = status.title
        self.detail = status.detail
        switch status.kind {
        case .success:
            self.tone = .success
        case .warning:
            self.tone = .warning
        case .failure:
            self.tone = .failure
        }
    }

    init(createFolderFeedback: FeedManagementCreateFolderFeedbackPresentation) {
        self.title = createFolderFeedback.title
        self.detail = createFolderFeedback.detail
        switch createFolderFeedback.kind {
        case .success:
            self.tone = .success
        case .failure:
            self.tone = .failure
        }
    }

    init(moveFeedFeedback: FeedManagementMoveFeedFeedbackPresentation) {
        self.title = moveFeedFeedback.title
        self.detail = moveFeedFeedback.detail
        switch moveFeedFeedback.kind {
        case .success:
            self.tone = .success
        case .failure:
            self.tone = .failure
        }
    }
}

enum FeedManagementFeedbackTone {
    case success
    case warning
    case failure

    var color: Color {
        switch self {
        case .success:
            .green
        case .warning:
            .orange
        case .failure:
            .red
        }
    }

    var systemImageName: String {
        switch self {
        case .success:
            "checkmark.circle.fill"
        case .warning:
            "exclamationmark.triangle.fill"
        case .failure:
            "xmark.octagon.fill"
        }
    }
}
