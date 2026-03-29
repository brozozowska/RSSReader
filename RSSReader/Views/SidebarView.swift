import SwiftUI

struct SidebarView: View {
    @Environment(\.appDependencies) private var dependencies
    @Binding var selection: SidebarSelection?
    @State private var feeds: [FeedSidebarItem] = []
    @State private var hasLoadedFeeds = false

    var body: some View {
        List(selection: $selection) {
            Label("Inbox", systemImage: "tray.full")
                .tag(Optional(SidebarSelection.inbox))

            Section("Feeds") {
                ForEach(feeds) { feed in
                    HStack {
                        Text(feed.title)
                        Spacer()
                        if feed.unreadCount > 0 {
                            Text(feed.unreadCount, format: .number)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                        .tag(Optional(SidebarSelection.feed(feed.id)))
                }
            }
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
            return
        }

        if let articleStateRepository = dependencies.articleStateRepository {
            do {
                let unreadCounts = try articleStateRepository.fetchUnreadCounts(feedIDs: feeds.map(\.id))
                feeds = feeds.map { feed in
                    feed.withUnreadCount(unreadCounts[feed.id, default: 0])
                }
            } catch {
                dependencies.logger.error("Failed to load unread counts for sidebar feeds: \(error)")
            }
        }

        if let selection {
            switch selection {
            case .inbox:
                break
            case .feed(let feedID):
                if feeds.contains(where: { $0.id == feedID }) == false {
                    self.selection = .inbox
                }
            }
        }
    }
}

#Preview {
    struct PreviewContainer: View {
        @State var selection: SidebarSelection? = .inbox
        var body: some View {
            SidebarView(selection: $selection)
        }
    }
    return PreviewContainer()
        .environment(\.appDependencies, AppDependencies.makeDefault())
}
