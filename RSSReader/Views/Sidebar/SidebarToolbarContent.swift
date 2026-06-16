import SwiftUI

struct SidebarToolbarContent: ToolbarContent {
    let toolbarState: SidebarToolbarState
    let selectedSidebarArticleFilter: SidebarArticleFilter
    let actionHandlers: SidebarActionHandlers

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: actionHandlers.showSettings) {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel(SidebarLocalization.settingsAccessibilityLabel)
        }

        ToolbarItem(placement: .title) {
            Text(SidebarLocalization.title)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        ToolbarItem(placement: .subtitle) {
            Text(toolbarState.subtitle)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }

        ToolbarItem(placement: .topBarTrailing) {
            Button(action: actionHandlers.showFeedManagement) {
                Image(systemName: "plus")
            }
            .accessibilityLabel(SidebarLocalization.addFeedAccessibilityLabel)
        }

        ToolbarSpacer(.fixed, placement: .topBarTrailing)

        ToolbarItem(placement: .topBarTrailing) {
            SidebarArticleFilterMenu(
                selectedSidebarArticleFilter: selectedSidebarArticleFilter,
                actionHandlers: actionHandlers
            )
        }
    }
}

private struct SidebarArticleFilterMenu: View {
    let selectedSidebarArticleFilter: SidebarArticleFilter
    let actionHandlers: SidebarActionHandlers

    var body: some View {
        Menu {
            sidebarArticleFilterButton(SidebarLocalization.allItemsFilterTitle, systemImage: "tray.full", filter: .allItems)
            sidebarArticleFilterButton(SidebarLocalization.unreadFilterTitle, systemImage: "circle", filter: .unread)
            sidebarArticleFilterButton(SidebarLocalization.starredFilterTitle, systemImage: "star", filter: .starred)
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .accessibilityLabel(SidebarLocalization.filterFeedsAccessibilityLabel)
    }

    @ViewBuilder
    private func sidebarArticleFilterButton(
        _ title: String,
        systemImage: String,
        filter: SidebarArticleFilter
    ) -> some View {
        Button {
            actionHandlers.applySidebarArticleFilter(filter)
        } label: {
            Label {
                HStack {
                    Text(title)
                    if selectedSidebarArticleFilter == filter {
                        Image(systemName: "checkmark")
                    }
                }
            } icon: {
                Image(systemName: systemImage)
            }
        }
    }
}
