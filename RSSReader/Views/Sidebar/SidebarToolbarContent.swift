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
            .accessibilityLabel("Settings")
        }

        ToolbarItem(placement: .title) {
            Text("Sources")
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
            .accessibilityLabel("Add Source")
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
            sourcesFilterButton("All Items", filter: .allItems)
            sourcesFilterButton("Unread", filter: .unread)
            sourcesFilterButton("Starred", filter: .starred)
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .accessibilityLabel("Filter Sources")
    }

    @ViewBuilder
    private func sourcesFilterButton(_ title: String, filter: SourcesFilter) -> some View {
        Button {
            actionHandlers.applySourcesFilter(filter)
        } label: {
            if selectedSourcesFilter == filter {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
    }
}
