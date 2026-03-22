import SwiftUI

struct ReaderView: View {
    let articleID: UUID?

    var body: some View {
        Group {
            if let id = articleID {
                Text("Reading article: \(id.uuidString)")
            } else {
                ContentUnavailableView("No Article Selected", systemImage: "doc.text")
            }
        }
        .navigationTitle("Reader")
    }
}

#Preview {
    ReaderView(articleID: nil)
}
