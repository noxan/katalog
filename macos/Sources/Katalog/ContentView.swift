import SwiftUI
import UniformTypeIdentifiers
import KatalogCore

private let epubType = UTType(filenameExtension: "epub") ?? .data

struct ContentView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var kindle: KindleWatcher
    @State private var importing = false
    @State private var selected: Book?

    private let columns = [GridItem(.adaptive(minimum: Theme.coverWidth), spacing: Theme.spacing)]

    var body: some View {
        ScrollView {
            if store.books.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: Theme.spacing) {
                    ForEach(store.books) { book in
                        BookCell(book: book)
                            .onTapGesture { selected = book }
                    }
                }
                .padding(Theme.spacing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .dropDestination(for: URL.self) { urls, _ in
            let epubs = urls.filter { $0.pathExtension.lowercased() == "epub" }
            for url in epubs { try? store.importBook(url) }
            return !epubs.isEmpty
        }
        .navigationTitle("Katalog")
        .toolbar {
            ToolbarItem {
                DeviceIndicator(devices: kindle.devices)
            }
            ToolbarItem {
                Button { importing = true } label: { Image(systemName: "plus") }
                    .help("Import epub")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [epubType],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                for url in urls { try? store.importBook(url) }
            }
        }
        .sheet(item: $selected) { DetailView(book: $0) }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48)).foregroundStyle(Theme.subtle)
            Text("Your library is empty")
                .font(.title3).foregroundStyle(Theme.text)
            Button("Import epub") { importing = true }
                .buttonStyle(.borderedProminent).tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, minHeight: 400)
    }
}

/// Persistent status pill: dim when no reader is mounted, frost when one is.
struct DeviceIndicator: View {
    let devices: [Device]
    var body: some View {
        let connected = !devices.isEmpty
        Label {
            Text(connected ? devices.map(\.name).joined(separator: ", ") : "No reader")
                .font(.system(size: 12))
        } icon: {
            Image(systemName: connected ? "externaldrive.fill.badge.checkmark" : "externaldrive")
        }
        .labelStyle(.titleAndIcon)
        .foregroundStyle(connected ? Theme.accent : Theme.subtle)
        .fixedSize()
        .help(connected ? "Reader connected" : "No reader mounted — unlock your Kindle and choose file transfer")
    }
}

struct BookCell: View {
    let book: Book
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverImage(path: book.coverPath)
                .frame(width: Theme.coverWidth, height: Theme.coverWidth * 1.5)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            Text(book.title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.text).lineLimit(2)
            Text(book.authors.joined(separator: ", "))
                .font(.system(size: 11))
                .foregroundStyle(Theme.subtle).lineLimit(1)
        }
        .frame(width: Theme.coverWidth)
    }
}

struct CoverImage: View {
    let path: String?
    var body: some View {
        if let path, let img = NSImage(contentsOfFile: path) {
            Image(nsImage: img).resizable().aspectRatio(contentMode: .fill).clipped()
        } else {
            Image(systemName: "book.closed")
                .font(.largeTitle).foregroundStyle(Theme.subtle)
        }
    }
}
