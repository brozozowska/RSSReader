import SwiftUI

struct SidebarView: View {
    @Binding var selection: UUID?

    private let feeds: [(id: UUID, title: String)] = [
        (UUID(), "All"),
        (UUID(), "Unread"),
        (UUID(), "Starred"),
        (UUID(), "Tech"),
        (UUID(), "News")
    ]

    var body: some View {
        List(feeds, id: \.id, selection: $selection) { feed in
            Text(feed.title)
        }
        .navigationTitle("Feeds")
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
}
