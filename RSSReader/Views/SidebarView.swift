import SwiftUI

struct SidebarView: View {
    @Environment(\.appDependencies) private var dependencies
    @Binding var selection: UUID?
    @State private var feeds: [FeedSidebarItem] = []
    @State private var hasLoadedFeeds = false

    var body: some View {
        List(feeds, id: \.id, selection: $selection) { feed in
            Text(feed.title)
        }
        .navigationTitle("Feeds")
        .overlay {
            if feeds.isEmpty && hasLoadedFeeds {
                ContentUnavailableView(
                    "No Feeds",
                    systemImage: "dot.radiowaves.left.and.right",
                    description: Text("Add a feed to populate the sidebar.")
                )
            }
        }
        .task {
            await loadFeeds()
        }
    }

    @MainActor
    private func loadFeeds() async {
        defer { hasLoadedFeeds = true }

        guard let feedRepository = dependencies.feedRepository else {
            feeds = []
            return
        }

        do {
            feeds = try feedRepository.fetchSidebarItems()
        } catch {
            dependencies.logger.error("Failed to load sidebar feeds: \(error)")
            feeds = []
        }

        if let selection, feeds.contains(where: { $0.id == selection }) == false {
            self.selection = feeds.first?.id
        }
    }
}

#Preview {
    struct PreviewContainer: View {
        @State var selection: UUID? = nil
        var body: some View {
            SidebarView(selection: $selection)
        }
    }
    return PreviewContainer()
        .environment(\.appDependencies, AppDependencies.makeDefault())
}
