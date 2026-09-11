import SwiftUI

struct SidebarSmartRowView: View {
    let row: SidebarSmartRowState

    var body: some View {
        SidebarBasicRow(
            title: row.title,
            iconSystemName: row.iconSystemName,
            count: row.count
        )
        .contentShape(Rectangle())
        .tag(row.selection)
    }
}

struct SidebarFeedRowView: View {
    let row: SidebarFeedRowState
    let isSelected: Bool
    let actionHandlers: SidebarActionHandlers

    var body: some View {
        HStack(spacing: 12) {
            FeedIconView(iconURL: row.iconURL)

            Text(row.title)
                .lineLimit(1)

            Spacer()

            if row.count > 0 {
                SidebarCountLabel(count: row.count)
            }
        }
        .font(.body)
        .padding(.leading, row.isIndented ? 24 : 0)
        .sidebarContextMenu(isSelected: isSelected) {
            Button {
                actionHandlers.showFeedOrganizer(row.id)
            } label: {
                Label(SidebarLocalization.organizeActionTitle, systemImage: "folder")
            }

            Button {
                actionHandlers.showFeedEditor(row.id)
            } label: {
                Label(SidebarLocalization.renameFeedActionTitle, systemImage: "pencil")
            }

            Button(role: .destructive) {
                actionHandlers.requestFeedUnsubscribeConfirmation(row.id, row.title)
            } label: {
                Label(SidebarLocalization.unsubscribeActionTitle, systemImage: "minus.circle")
            }
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .tag(row.selection)
    }
}

struct SidebarFolderRowView: View {
    let row: SidebarFolderRowState
    @Binding var selection: SidebarSelection?
    let actionHandlers: SidebarActionHandlers
    let onFolderExpansionToggle: (String) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button {
                onFolderExpansionToggle(row.name)
            } label: {
                Image(systemName: row.isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 12)
            }
            .buttonStyle(.plain)

            Button {
                selection = row.selection
            } label: {
                Text(row.name)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            Spacer()
            if row.count > 0 {
                SidebarCountLabel(count: row.count)
            }
        }
        .font(.body)
        .sidebarContextMenu(isSelected: selection == row.selection) {
            Button {
                actionHandlers.showFolderEditor(row.name)
            } label: {
                Label(SidebarLocalization.renameFolderActionTitle, systemImage: "pencil")
            }

            Button(role: .destructive) {
                actionHandlers.requestFolderDeleteConfirmation(row.name)
            } label: {
                Label(SidebarLocalization.deleteActionTitle, systemImage: "trash")
            }
        }
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
        .tag(row.selection)
    }
}

private extension View {
    func sidebarContextMenu<MenuItems: View>(
        isSelected: Bool,
        @ViewBuilder menuItems: () -> MenuItems
    ) -> some View {
        SidebarContextMenuRow(content: self, isSelected: isSelected, menuItems: menuItems())
            .listRowInsets(EdgeInsets())
    }
}

private struct SidebarContextMenuRow<Content: View, MenuItems: View>: View {
    @Environment(\.self) private var sourceEnvironment
    @Environment(\.appThemeVariant) private var appThemeVariant
    @State private var rowWidth: CGFloat = 0
    let content: Content
    let isSelected: Bool
    let menuItems: MenuItems

    var body: some View {
        // Resolve the environment while still in the List's hierarchy, before
        // UIKit evaluates the preview in a separate hosting hierarchy.
        let previewEnvironment = sourceEnvironment

        return content
            .modifier(SidebarContextMenuRowLayout())
            .background {
                // Preserve the native selection underneath a selected row.
                // Other rows need an opaque surface even during the initial lift.
                if !isSelected {
                    Capsule(style: .continuous)
                        .fill(appThemeVariant.primaryBackground)
                }
            }
            .onGeometryChange(for: CGFloat.self) { geometry in
                geometry.size.width
            } action: { width in
                rowWidth = width
            }
            .contextMenu {
                menuItems
            } preview: {
                SidebarContextMenuPreview(
                    content: content,
                    rowWidth: rowWidth,
                    sourceEnvironment: previewEnvironment
                )
            }
    }
}

struct SidebarContextMenuPreview<Content: View>: View {
    let content: Content
    let rowWidth: CGFloat
    let sourceEnvironment: EnvironmentValues

    var body: some View {
        content
            .modifier(SidebarContextMenuRowLayout())
            .frame(width: rowWidth > 0 ? rowWidth : nil)
            .fixedSize(horizontal: false, vertical: true)
            .background(sourceEnvironment.appThemeVariant.contextMenuPreviewBackground, in: Capsule(style: .continuous))
            .environment(\.backgroundProminence, .standard)
            .allowsHitTesting(false)
            .environment(\.self, sourceEnvironment)
    }
}

private struct SidebarContextMenuRowLayout: ViewModifier {
    @Environment(\.defaultMinListRowHeight) private var minimumListRowHeight

    func body(content: Content) -> some View {
        // Include the row insets in the preview's bounds. A shape on the bare
        // HStack only covers the text/icon height, producing a thin lifted strip.
        content
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: max(52, minimumListRowHeight))
            .contentShape(.interaction, Rectangle())
            .contentShape(.contextMenuPreview, Capsule(style: .continuous))
    }
}

struct SidebarSectionHeader: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
    }
}

private struct SidebarBasicRow: View {
    let title: String
    let iconSystemName: String
    let count: Int?
    let leadingPadding: CGFloat

    init(
        title: String,
        iconSystemName: String,
        count: Int?,
        leadingPadding: CGFloat = 0
    ) {
        self.title = title
        self.iconSystemName = iconSystemName
        self.count = count
        self.leadingPadding = leadingPadding
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconSystemName)
                .font(.body.weight(.medium))
                .frame(width: 20)
                .foregroundStyle(.primary)

            Text(title)
                .lineLimit(1)

            Spacer()

            if let count, count > 0 {
                SidebarCountLabel(count: count)
            }
        }
        .font(.body)
        .padding(.leading, leadingPadding)
        .listRowSeparator(.hidden)
        .listRowBackground(Color.clear)
    }
}

private struct SidebarCountLabel: View {
    let count: Int

    var body: some View {
        Text(count, format: .number)
            .font(.callout)
            .foregroundStyle(.secondary)
    }
}
