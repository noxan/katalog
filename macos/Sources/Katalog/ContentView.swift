import SwiftUI
import UniformTypeIdentifiers
import KatalogCore

private let epubType = UTType(filenameExtension: "epub") ?? .data

struct ContentView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var kindle: KindleWatcher
    @State private var importing = false
    @State private var selected: Book?
    @State private var prompts: [DuplicatePrompt] = []

    private let columns = [GridItem(.adaptive(minimum: Theme.coverWidth), spacing: Theme.spacing)]

    var body: some View {
        ScrollView {
            if store.books.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: Theme.spacing) {
                    ForEach(store.books) { book in
                        BookCell(book: book, onDevice: kindle.onDevice(book))
                            .onTapGesture { selected = book }
                    }
                }
                .padding(Theme.spacing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .safeAreaInset(edge: .bottom) {
            StatusBar(bookCount: store.books.count, devices: kindle.devices)
        }
        .dropDestination(for: URL.self) { urls, _ in
            let epubs = urls.filter { $0.pathExtension.lowercased() == "epub" }
            prompts = store.importBatch(epubs)
            return !epubs.isEmpty
        }
        .navigationTitle("Katalog")
        .toolbar {
            ToolbarItem {
                Button { importing = true } label: { Image(systemName: "plus") }
                    .help("Import epub")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [epubType],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                prompts = store.importBatch(urls)
            }
        }
        .sheet(item: $selected) { DetailView(book: $0) }
        .sheet(isPresented: Binding(get: { !prompts.isEmpty },
                                    set: { if !$0 { prompts = [] } })) {
            if let current = prompts.first {
                DuplicateDialog(
                    prompt: current, remaining: prompts.count,
                    onResolve: { importAnyway, applyToAll in
                        resolve(importAnyway: importAnyway, applyToAll: applyToAll)
                    },
                    onCancel: { prompts = [] }
                )
            }
        }
    }

    /// Apply the user's decision to the current duplicate — or, with
    /// "apply to all", to every remaining one — then advance the queue.
    private func resolve(importAnyway: Bool, applyToAll: Bool) {
        if applyToAll {
            if importAnyway { for p in prompts { try? store.importBook(p.url) } }
            prompts = []
        } else {
            let p = prompts.removeFirst()
            if importAnyway { try? store.importBook(p.url) }
        }
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

/// Bottom status bar: book count on the left, reader status on the right.
struct StatusBar: View {
    let bookCount: Int
    let devices: [Device]

    var body: some View {
        let connected = !devices.isEmpty
        HStack(spacing: 6) {
            Text("\(bookCount) book\(bookCount == 1 ? "" : "s")")
                .foregroundStyle(Theme.subtle)
            Spacer()
            Image(systemName: connected ? "externaldrive.fill.badge.checkmark" : "externaldrive")
            Text(connected ? devices.map(\.name).joined(separator: ", ") : "No reader")
        }
        .font(.system(size: 12))
        .foregroundStyle(connected ? Theme.accent : Theme.subtle)
        .padding(.horizontal, Theme.spacing)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .overlay(alignment: .top) { Divider().overlay(Theme.subtle.opacity(0.2)) }
        .help(connected ? "Reader connected" : "No reader mounted — unlock your Kindle and choose file transfer")
    }
}

struct BookCell: View {
    let book: Book
    var onDevice: Bool = false
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverImage(path: book.coverPath)
                .frame(width: Theme.coverWidth, height: Theme.coverWidth * 1.5)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                .overlay(alignment: .topTrailing) {
                    if onDevice {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(Theme.accent)
                            .padding(6)
                            .help("On your reader")
                    }
                }
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
