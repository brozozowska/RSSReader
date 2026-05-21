import SwiftUI

struct ArticleListSectionHeaderView: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
            .padding(.horizontal, ArticleListSectionHeaderLayout.horizontalPadding)
            .padding(.vertical, ArticleListSectionHeaderLayout.verticalPadding)
            .sectionHeaderBackground()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum ArticleListSectionHeaderLayout {
    static let horizontalPadding: CGFloat = 8
    static let verticalPadding: CGFloat = 3
}

private extension View {
    func sectionHeaderBackground() -> some View {
        glassEffect(.regular, in: .capsule)
    }
}
