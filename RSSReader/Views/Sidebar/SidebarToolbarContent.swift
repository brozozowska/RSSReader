import SwiftUI

struct SidebarToolbarContent: ToolbarContent {
    let selectedSidebarArticleFilter: SidebarArticleFilter
    let actionHandlers: SidebarActionHandlers

    var body: some ToolbarContent {
        ToolbarItem(placement: SidebarToolbarPlacement.settings) {
            Button(action: actionHandlers.showSettings) {
                Image(systemName: "gearshape")
            }
            .accessibilityLabel(SidebarLocalization.settingsAccessibilityLabel)
        }

        ToolbarItem(placement: SidebarToolbarPlacement.addFeed) {
            Button(action: actionHandlers.showFeedManagement) {
                Image(systemName: "plus")
            }
            .accessibilityLabel(SidebarLocalization.addFeedAccessibilityLabel)
        }

        ToolbarSpacer(.fixed, placement: .topBarTrailing)

        ToolbarItem(placement: SidebarToolbarPlacement.filter) {
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
            sidebarArticleFilterButton(SidebarLocalization.unreadFilterTitle, systemImage: ArticleStateSymbols.read(isRead: false), filter: .unread)
            sidebarArticleFilterButton(SidebarLocalization.starredFilterTitle, systemImage: ArticleStateSymbols.starred(isStarred: true), filter: .starred)
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
