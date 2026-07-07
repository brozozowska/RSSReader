import SwiftUI

struct SidebarSmartRowView: View {
    let row: SidebarSmartRowState
    @Binding var selection: SidebarSelection?

    var body: some View {
        SidebarBasicRow(
            title: row.title,
            iconSystemName: row.iconSystemName,
            count: row.count
        )
        .contentShape(Rectangle())
        .onTapGesture {
            selection = row.selection
        }
        .tag(Optional(row.selection))
    }
}

struct SidebarFeedRowView: View {
    let row: SidebarFeedRowState
    @Binding var selection: SidebarSelection?
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
        .contentShape(Rectangle())
        .onTapGesture {
            selection = row.selection
        }
        .contextMenu {
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
        .tag(Optional(row.selection))
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
                actionHandlers.showFolder(row.name)
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
        .contextMenu {
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
        .tag(Optional(row.selection))
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
