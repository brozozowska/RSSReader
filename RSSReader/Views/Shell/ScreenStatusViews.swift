import SwiftUI

struct ScreenLoadingView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    let title: String

    var body: some View {
        VStack(spacing: 12) {
            AppRefreshIndicator(
                state: .refreshing,
                size: 22,
                lineWidth: 2.5
            )

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(appThemeVariant.primaryBackground)
    }
}

struct ScreenPlaceholderView: View {
    @Environment(\.appThemeVariant) private var appThemeVariant
    let title: String
    let systemImage: String
    let description: String?
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        title: String,
        systemImage: String,
        description: String? = nil,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.description = description
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage)
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(.secondary)

            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)

            if let description, description.isEmpty == false {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
        .background(appThemeVariant.primaryBackground)
    }
}
