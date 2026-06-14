import SwiftUI

struct SidebarToolbarContent: ToolbarContent {
    let toolbarState: SidebarToolbarState
    let selectedSourcesFilter: SourcesFilter
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
            Button(action: actionHandlers.showSourceManagement) {
                Image(systemName: "plus")
            }
            .accessibilityLabel(SidebarLocalization.addSourceAccessibilityLabel)
        }

        ToolbarSpacer(.fixed, placement: .topBarTrailing)

        ToolbarItem(placement: .topBarTrailing) {
            SidebarSourcesFilterMenu(
                selectedSourcesFilter: selectedSourcesFilter,
                actionHandlers: actionHandlers
            )
        }
    }
}

private struct SidebarSourcesFilterMenu: View {
    let selectedSourcesFilter: SourcesFilter
    let actionHandlers: SidebarActionHandlers

    var body: some View {
        Menu {
            sourcesFilterButton(SidebarLocalization.allItemsFilterTitle, systemImage: "tray.full", filter: .allItems)
            sourcesFilterButton(SidebarLocalization.unreadFilterTitle, systemImage: "circle", filter: .unread)
            sourcesFilterButton(SidebarLocalization.starredFilterTitle, systemImage: "star", filter: .starred)
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .accessibilityLabel(SidebarLocalization.filterSourcesAccessibilityLabel)
    }

    @ViewBuilder
    private func sourcesFilterButton(
        _ title: String,
        systemImage: String,
        filter: SourcesFilter
    ) -> some View {
        Button {
            actionHandlers.applySourcesFilter(filter)
        } label: {
            Label {
                HStack {
                    Text(title)
                    if selectedSourcesFilter == filter {
                        Image(systemName: "checkmark")
                    }
                }
            } icon: {
                Image(systemName: systemImage)
            }
        }
    }
}
