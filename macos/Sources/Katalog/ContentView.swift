import SwiftUI
import AppKit
import UniformTypeIdentifiers
import KatalogCore

private let epubType = UTType(filenameExtension: "epub") ?? .data

/// The single modal a book cell can open — detail or metadata editor.
private enum BookSheet: Identifiable {
    case detail(Book), edit(Book)
    var id: String {
        switch self {
        case .detail(let b): return "detail-\(b.id)"
        case .edit(let b): return "edit-\(b.id)"
        }
    }
}

/// Everything the display order depends on — the trigger for re-sorting.
private struct OrderKey: Equatable {
    let books: [Book]
    let sort: SortOrder
    let group: Grouping
}

struct ContentView: View {
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var kindle: KindleWatcher
    @State private var importing = false
    // One sheet route: stacking two .sheet(item:) on the same view leaves the
    // second binding stuck after first dismiss, so a second edit won't open.
    @State private var sheet: BookSheet?
    @State private var prompts: [DuplicatePrompt] = []
    @State private var searchText = ""
    @AppStorage("gridStyle") private var gridStyle: GridStyle = .compact
    @AppStorage("sortOrder") private var sortOrder: SortOrder = .dateAdded
    @AppStorage("grouping") private var grouping: Grouping = .series
    // ponytail: display preferences live in Settings; read here to render.
    /// The library in display order. Sorting runs localizedStandardCompare per
    /// comparison, and body re-runs on every store/watcher change, so keep the
    /// result until its inputs actually change.
    @State private var ordered: [Book] = []

    private let columns = [GridItem(.adaptive(minimum: Theme.coverWidth), spacing: Theme.spacing)]

    var body: some View {
        ScrollView {
            if store.books.isEmpty {
                emptyState
            } else if visibleBooks.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxWidth: .infinity, minHeight: 400)
            } else {
                LazyVGrid(columns: columns, spacing: Theme.spacing) {
                    ForEach(visibleBooks) { book in
                        Button { sheet = .detail(book) } label: {
                            BookCell(book: book, onDevice: kindle.onDevice(book), style: gridStyle)
                        }
                        .buttonStyle(.plain)
                            .contextMenu { bookMenu(book) }
                    }
                }
                .padding(Theme.spacing)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        // Array equality short-circuits on identical storage, so an unchanged
        // library costs a pointer compare here, not a re-sort.
        .onChange(of: OrderKey(books: store.books, sort: sortOrder, group: grouping),
                  initial: true) {
            ordered = grouping.sorted(store.books, by: sortOrder)
        }
        .safeAreaInset(edge: .bottom) {
            StatusBar(bookCount: store.books.count, devices: kindle.devices, scanning: kindle.scanning,
                      scanDone: kindle.scanProgress.done, scanTotal: kindle.scanProgress.total,
                      jobs: kindle.jobs, failure: kindle.lastFailure) { kindle.lastFailure = nil }
        }
        .dropDestination(for: URL.self) { urls, _ in
            let epubs = store.epubURLs(from: urls)
            Task { prompts = await store.importBatch(epubs) }
            return !epubs.isEmpty
        }
        // Files opened via Finder "Open With" (default-app handler). onOpenURL
        // fires once per URL; append so a multi-file open keeps every prompt.
        .onOpenURL { url in
            Task { prompts += await store.importBatch(store.epubURLs(from: [url])) }
        }
        .navigationTitle("Katalog")
        .searchable(text: $searchText, placement: .toolbar, prompt: "Find in Books")
        .toolbar {
            ToolbarItemGroup {
                libraryOptions
                Button { importing = true } label: { Image(systemName: "plus") }
                    .keyboardShortcut("o", modifiers: .command)
                    .help("Import epubs or a folder (⌘O)")
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .importBooks)) { _ in importing = true }
        .onReceive(NotificationCenter.default.publisher(for: .editCurrentBook)) { _ in
            if case .detail(let book) = sheet { sheet = .edit(book) }
        }
        .onReceive(NotificationCenter.default.publisher(for: .revealCurrentBook)) { _ in
            guard let book = currentBook else { return }
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: book.filePath)])
        }
        .onReceive(NotificationCenter.default.publisher(for: .removeCurrentBook)) { _ in
            guard let book = currentBook else { return }
            sheet = nil
            store.remove(book)
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [epubType, .folder],
                      allowsMultipleSelection: true) { result in
            if case .success(let urls) = result {
                Task { prompts = await store.importBatch(store.epubURLs(from: urls)) }
            }
        }
        .sheet(item: $sheet) { route in
            switch route {
            case .detail(let book): DetailView(book: book)
            case .edit(let book): EditView(book: book) { _ in }
            }
        }
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

    private var visibleBooks: [Book] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return ordered }
        return ordered.filter { book in
            ([book.title] + book.authors + [book.series, book.publisher, book.isbn].compactMap { $0 })
                .contains { $0.localizedCaseInsensitiveContains(query) }
        }
    }

    /// Music-style toolbar menu keeps ordering and presentation controls near
    /// the collection they affect, without permanently occupying toolbar space.
    private var libraryOptions: some View {
        Menu {
            Menu("Sort By", systemImage: "arrow.up.arrow.down") {
                ForEach(SortOrder.allCases, id: \.self) { order in
                    optionButton(order.label, selected: sortOrder == order) { sortOrder = order }
                }
            }
            Menu("Group By", systemImage: "rectangle.3.group") {
                ForEach(Grouping.allCases, id: \.self) { group in
                    optionButton(group.label, selected: grouping == group) { grouping = group }
                }
            }
            Divider()
            Menu("View Options", systemImage: "rectangle.grid.2x2") {
                optionButton("Titles and Authors", selected: gridStyle == .compact) { gridStyle = .compact }
                optionButton("Covers Only", selected: gridStyle == .covers) { gridStyle = .covers }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .help("Sort, group, and view options")
    }

    private func optionButton(_ title: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            if selected { Label(title, systemImage: "checkmark") }
            else { Text(title) }
        }
    }

    private var currentBook: Book? {
        switch sheet {
        case .detail(let book), .edit(let book): return book
        case nil: return nil
        }
    }

    /// Apply the user's decision to the current duplicate — or, with
    /// "apply to all", to every remaining one — then advance the queue.
    private func resolve(importAnyway: Bool, applyToAll: Bool) {
        if applyToAll {
            let urls = prompts.map(\.url)
            prompts = []
            if importAnyway { Task { await store.importAll(urls) } }
        } else {
            let p = prompts.removeFirst()
            if importAnyway { Task { try? await store.importBook(p.url) } }
        }
    }

    // Same actions as DetailView's overflow/context menu.
    @ViewBuilder private func bookMenu(_ book: Book) -> some View {
        Button { sheet = .edit(book) } label: {
            Label("Edit Metadata…", systemImage: "pencil")
        }
        .keyboardShortcut("e", modifiers: .command)
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: book.filePath)])
        } label: {
            Label("Show in Finder", systemImage: "folder")
        }
        .keyboardShortcut("r", modifiers: [.command, .shift])
        Divider()
        Button(role: .destructive) {
            store.remove(book)
        } label: {
            Label("Remove from Library", systemImage: "trash")
        }
        .keyboardShortcut(.delete, modifiers: .command)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "books.vertical")
                .font(.system(size: 48)).foregroundStyle(Theme.subtle)
            Text("Your library is empty")
                .font(.title3).foregroundStyle(Theme.text)
            Button { importing = true } label: {
                Label("Import epub", systemImage: "plus")
            }
            .keyboardShortcut("o", modifiers: .command)
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
    var scanDone: Int = 0
    var scanTotal: Int = 0
    var jobs: [KindleJob] = []
    var failure: String?
    var onDismissFailure: () -> Void = {}
    @State private var hoverReader = false

    var body: some View {
        let connected = !devices.isEmpty
        let icon = !connected ? "externaldrive"
            : (scanning ? "externaldrive.fill" : "externaldrive.fill.badge.checkmark")
        HStack(spacing: 6) {
            Text("\(bookCount) book\(bookCount == 1 ? "" : "s")")
            jobStatus
            Spacer()
            if connected {
                Menu {
                    deviceActions
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: icon)
                        Text(scanning
                             ? "Scanning \(devices.map(\.name).joined(separator: ", ")) "
                               + "\(scanDone) of \(scanTotal)…"
                             : devices.map(\.name).joined(separator: ", "))
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

    /// In-flight sends/removes, or the last failure (click to dismiss). Sits
    /// next to the book count so background work stays visible after the detail
    /// page closes.
    @ViewBuilder private var jobStatus: some View {
        if let failure {
            Button(action: onDismissFailure) {
                Label(failure, systemImage: "exclamationmark.triangle.fill")
            }
            .buttonStyle(.plain).foregroundStyle(.red).help("Click to dismiss")
        } else if !jobs.isEmpty {
            ProgressView().controlSize(.small).scaleEffect(0.7)
            Text(jobs.count == 1 ? "\(jobs[0].verb) \(jobs[0].title)…" : "\(jobs.count) transfers…")
        }
    }

    @ViewBuilder private var deviceActions: some View {
        ForEach(devices) { device in
            Button {
                // `open` asks Launch Services to open the volume as a document,
                // which macOS rejects for sandboxed apps even when removable-
                // volume access is granted. Ask Finder to reveal its documents
                // folder instead; this opens the same device without that check.
                NSWorkspace.shared.activateFileViewerSelecting([device.documents])
            } label: {
                Label("Open \(device.name) in Finder", systemImage: "folder")
            }
            Button {
                try? NSWorkspace.shared.unmountAndEjectDevice(at: device.volume)
            } label: {
                Label("Eject \(device.name)", systemImage: "eject")
            }
        }
    }
}

/// How grid cells present a book's title/author.
enum GridStyle: String, CaseIterable {
    case compact  // single-line title + author beneath the cover
    case covers   // covers only; caption fades in on hover
}

/// How the catalog is ordered. `dateAdded` (newest first) is the default and
/// matches the core's SQL ordering; the rest sort in memory.
enum SortOrder: String, CaseIterable {
    case dateAdded, title, author

    var label: String {
        switch self {
        case .dateAdded: return "Date added"
        case .title: return "Title"
        case .author: return "Author"
        }
    }

    // ponytail: added_at is an ISO string, so reverse-lexicographic = newest first.
    func comesBefore(_ lhs: Book, _ rhs: Book) -> Bool {
        switch self {
        case .dateAdded: return false  // core already returns added_at DESC
        case .title: return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        case .author: return (lhs.authors.first ?? "").localizedStandardCompare(rhs.authors.first ?? "") == .orderedAscending
        }
    }

    func sorted(_ books: [Book]) -> [Book] {
        self == .dateAdded ? books : books.sorted(by: comesBefore)
    }
}

enum Grouping: String, CaseIterable {
    case none, series

    var label: String { self == .none ? "None" : "Series" }

    func sorted(_ books: [Book], by sortOrder: SortOrder) -> [Book] {
        guard self == .series else { return sortOrder.sorted(books) }
        return books.sorted {
            let authorComparison = ($0.authors.first ?? "").localizedStandardCompare($1.authors.first ?? "")
            if authorComparison != .orderedSame { return authorComparison == .orderedAscending }
            let lhs = $0.series?.trimmingCharacters(in: .whitespacesAndNewlines)
            let rhs = $1.series?.trimmingCharacters(in: .whitespacesAndNewlines)
            switch (lhs?.isEmpty == false ? lhs : nil, rhs?.isEmpty == false ? rhs : nil) {
            case let (lhs?, rhs?):
                let comparison = lhs.localizedStandardCompare(rhs)
                if comparison != .orderedSame { return comparison == .orderedAscending }
                if $0.seriesIndex != $1.seriesIndex { return ($0.seriesIndex ?? .greatestFiniteMagnitude) < ($1.seriesIndex ?? .greatestFiniteMagnitude) }
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): break
            }
            return sortOrder.comesBefore($0, $1)
        }
    }
}

struct BookCell: View {
    let book: Book
    var onDevice: Bool = false
    var style: GridStyle = .compact
    @State private var hover = false

    private var authors: String { book.authors.joined(separator: ", ") }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            CoverImage(path: book.coverPath, title: book.title, authors: authors)
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
                .overlay(alignment: .topLeading) {
                    if let index = book.seriesIndex {
                        Text("#\(EditView.formatIndex(index))")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(.black.opacity(0.7), in: Capsule())
                            .padding(6)
                            .help("Book \(EditView.formatIndex(index)) in \(book.series ?? "series")")
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
        // Fill the whole grid column so hover/tap map 1:1 to this book. The
        // adaptive columns are wider than coverWidth; without this each cover
        // is a narrow frame with dead gaps, and hits drift to the neighbor.
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
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

/// Decoded cover thumbnails, keyed by path + pixel size. Covers are stored at
/// the epub's own resolution (often 1600px tall) while cells draw them at 150pt,
/// so decoding the original inside `body` was the dominant grid cost — and kept
/// a full-size bitmap alive per visible cell.
/// ponytail: NSCache evicts under pressure, and the key is the content-versioned
/// cover filename, so there is nothing to invalidate by hand.
private let coverCache = NSCache<NSString, NSImage>()

/// Decode straight to the target size — Image I/O never materializes the
/// full-resolution bitmap.
private func decodeCover(_ path: String, maxPixel: Int) -> NSImage? {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, [
              kCGImageSourceCreateThumbnailFromImageAlways: true,
              kCGImageSourceCreateThumbnailWithTransform: true,
              kCGImageSourceThumbnailMaxPixelSize: maxPixel,
          ] as CFDictionary)
    else { return nil }
    return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
}

struct CoverImage: View {
    let path: String?
    var title: String = ""
    var authors: String = ""
    /// Longest edge to decode — Theme.coverHeight at 2x covers every call site,
    /// including the detail view's blurred backdrop.
    var maxPixel: Int = Int(Theme.coverHeight * 2)
    @State private var decoded: NSImage?

    private var cacheKey: NSString? { path.map { "\($0)@\(maxPixel)" as NSString } }

    var body: some View {
        // Read the cache in body so a re-render of an already-decoded cover
        // draws immediately instead of flashing the placeholder.
        let image = decoded ?? cacheKey.flatMap { coverCache.object(forKey: $0) }
        Group {
            if let image {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill).clipped()
            } else {
                placeholder
            }
        }
        .task(id: cacheKey) {
            guard let path, let key = cacheKey, coverCache.object(forKey: key) == nil else { return }
            let size = maxPixel
            let image = await Task.detached(priority: .userInitiated) {
                decodeCover(path, maxPixel: size)
            }.value
            if let image { coverCache.setObject(image, forKey: key) }
            decoded = image
        }
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "book.closed")
                .font(.largeTitle).foregroundStyle(Theme.subtle)
            if !title.isEmpty {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(3)
                Text(authors)
                    .font(.system(size: 10))
                    .foregroundStyle(Theme.subtle)
                    .lineLimit(2)
            }
        }
        .multilineTextAlignment(.center)
        .padding(10)
    }
}
