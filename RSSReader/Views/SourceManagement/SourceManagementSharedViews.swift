import SwiftUI

struct SourceManagementCloseButton: View {
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
        }
        .accessibilityLabel(accessibilityLabel)
    }
}

struct SourceManagementScreenItemCard: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    let item: SourceManagementScreenItemPresentation

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

                    Text(item.badgeTitle)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(appThemeVariant.secondaryBackground)
                        .clipShape(Capsule())
                }

                Text(item.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 6)
    }
}
struct SourceManagementFolderPlacementRow: View {
    let option: SourceManagementFolderPlacementOptionPresentation

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
struct SourceManagementFeedbackCard: View {
    let feedback: SourceManagementFeedbackCardPresentation

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

struct SourceManagementFeedbackCardPresentation {
    let title: String
    let detail: String?
    let tone: SourceManagementFeedbackTone

    init(status: SourceManagementAddFeedStatusPresentation) {
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

    init(createFolderFeedback: SourceManagementCreateFolderFeedbackPresentation) {
        self.title = createFolderFeedback.title
        self.detail = createFolderFeedback.detail
        switch createFolderFeedback.kind {
        case .success:
            self.tone = .success
        case .failure:
            self.tone = .failure
        }
    }

    init(moveSourceFeedback: SourceManagementMoveSourceFeedbackPresentation) {
        self.title = moveSourceFeedback.title
        self.detail = moveSourceFeedback.detail
        switch moveSourceFeedback.kind {
        case .success:
            self.tone = .success
        case .failure:
            self.tone = .failure
        }
    }
}

enum SourceManagementFeedbackTone {
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
