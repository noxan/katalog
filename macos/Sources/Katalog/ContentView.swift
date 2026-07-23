import SwiftUI
import AppKit
import UniformTypeIdentifiers
import KatalogCore

private let epubType = UTType(filenameExtension: "epub") ?? .data

struct ContentView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var kindle: KindleWatcher
    @State private var importing = false
    @State private var selected: Book?
    @State private var prompts: [DuplicatePrompt] = []
    @AppStorage("gridStyle") private var gridStyle: GridStyle = .compact

    private let columns = [GridItem(.adaptive(minimum: Theme.coverWidth), spacing: Theme.spacing)]

    var body: some View {
        ScrollView {
            if store.books.isEmpty {
                emptyState
            } else {
                LazyVGrid(columns: columns, spacing: Theme.spacing) {
                    ForEach(store.books) { book in
                        BookCell(book: book, onDevice: kindle.onDevice(book), style: gridStyle)
                            .onTapGesture { selected = book }
                    }
                }
                .padding(Theme.spacing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .safeAreaInset(edge: .bottom) {
            StatusBar(bookCount: store.books.count, devices: kindle.devices, scanning: kindle.scanning)
        }
        .dropDestination(for: URL.self) { urls, _ in
            let epubs = store.epubURLs(from: urls)
            prompts = store.importBatch(epubs)
            return !epubs.isEmpty
        }
        // Files opened via Finder "Open With" (default-app handler). onOpenURL
        // fires once per URL; append so a multi-file open keeps every prompt.
        .onOpenURL { url in
            prompts += store.importBatch(store.epubURLs(from: [url]))
        }
        .navigationTitle("Katalog")
        .toolbar {
            ToolbarItem {
                Picker("View", selection: $gridStyle) {
                    Image(systemName: "text.below.photo").tag(GridStyle.compact)
                    Image(systemName: "square.grid.2x2").tag(GridStyle.covers)
                }
                .pickerStyle(.segmented)
                .help("Grid style")
            }
            ToolbarSpacer(.fixed)
            ToolbarItem {
                Button { importing = true } label: { Image(systemName: "plus") }
                    .help("Import epubs or a folder")
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [epubType, .folder],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                prompts = store.importBatch(store.epubURLs(from: urls))
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
    var scanning: Bool = false
    @State private var hoverReader = false

    var body: some View {
        let connected = !devices.isEmpty
        let icon = !connected ? "externaldrive"
            : (scanning ? "externaldrive.fill" : "externaldrive.fill.badge.checkmark")
        HStack(spacing: 6) {
            Text("\(bookCount) book\(bookCount == 1 ? "" : "s")")
            Spacer()
            if connected {
                Menu {
                    deviceActions
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                        Text(devices.map(\.name).joined(separator: ", "))
                    }
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5)
                        .fill(hoverReader ? Color.primary.opacity(0.1) : .clear))
                    .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .onHover { hoverReader = $0 }
                .contextMenu { deviceActions }
                if scanning { ProgressView().controlSize(.small) }
            } else {
                Image(systemName: icon)
                Text("No reader")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(.bar)
        .overlay(alignment: .top) { Divider() }
        .help(!connected ? "No reader mounted — unlock your Kindle and choose file transfer"
              : (scanning ? "Reading books on the reader…" : "Reader connected"))
    }

    @ViewBuilder private var deviceActions: some View {
        ForEach(devices) { device in
            Button("Open \(device.name) in Finder") {
                NSWorkspace.shared.open(device.volume)
            }
            Button("Eject \(device.name)") {
                try? NSWorkspace.shared.unmountAndEjectDevice(at: device.volume)
            }
        }
    }
}

/// How grid cells present a book's title/author.
enum GridStyle: String, CaseIterable {
    case compact  // single-line title + author beneath the cover
    case covers   // covers only; caption fades in on hover
}

struct BookCell: View {
    let book: Book
    var onDevice: Bool = false
    var style: GridStyle = .compact
    @State private var hover = false

    private var authors: String { book.authors.joined(separator: ", ") }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverImage(path: book.coverPath)
                .frame(width: Theme.coverWidth, height: Theme.coverHeight)
                .background(Theme.surface)
                .overlay(alignment: .bottom) {
                    if style == .covers && hover { hoverCaption }
                }
                .overlay(alignment: .topTrailing) {
                    if onDevice {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 17))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, Theme.accent)
                            .shadow(color: .black.opacity(0.5), radius: 2)
                            .padding(6)
                            .help("On your reader")
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                .animation(.easeInOut(duration: 0.15), value: hover)

            if style == .compact {
                // One line each — no reserved gap, uniform cell height.
                VStack(alignment: .leading, spacing: 2) {
                    Text(book.title)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Theme.text)
                        .lineLimit(1).truncationMode(.tail)
                    Text(authors)
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.subtle)
                        .lineLimit(1).truncationMode(.tail)
                }
            }
        }
        .frame(width: Theme.coverWidth, alignment: .leading)
        .onHover { hover = $0 }
    }

    private var hoverCaption: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(book.title)
                .font(.system(size: 12, weight: .semibold))
                .lineLimit(2)
            Text(authors)
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
        }
        .foregroundStyle(.white)
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(colors: [.black.opacity(0.9), .black.opacity(0)],
                           startPoint: .bottom, endPoint: .top)
        )
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
