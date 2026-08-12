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
        Group {
            if store.books.isEmpty {
                // Keep the welcome view outside ScrollView: a scroll view gives
                // its content no finite height, so vertical spacers collapse and
                // make the artwork appear too high instead of truly centered.
                emptyState
            } else {
                ScrollView {
                    if visibleBooks.isEmpty {
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
        // Book commands are disabled while no detail/editor is active. This is
        // important for text fields: otherwise ⌘Delete is stolen from Search.
        .focusedValue(\.currentBook, currentBook)
        .searchable(text: $searchText, placement: .toolbar, prompt: "Find in Books")
        .toolbar {
            // Reader state is global, so give it a standalone leading position
            // rather than grouping it with the trailing library controls.
            ToolbarItem(placement: .navigation) {
                ReaderToolbarMenu(
                    devices: kindle.devices,
                    scanning: kindle.scanning,
                    scanDone: kindle.scanProgress.done,
                    scanTotal: kindle.scanProgress.total,
                    jobs: kindle.jobs,
                    failure: kindle.lastFailure,
                    onDismissFailure: { kindle.lastFailure = nil }
                )
            }
            ToolbarItemGroup(placement: .primaryAction) {
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
                    optionToggle(order.label, selected: sortOrder == order) { sortOrder = order }
                }
            }
            Menu("Group By", systemImage: "rectangle.3.group") {
                ForEach(Grouping.allCases, id: \.self) { group in
                    optionToggle(group.label, selected: grouping == group) { grouping = group }
                }
            }
            Divider()
            Menu("View Options", systemImage: "rectangle.grid.2x2") {
                optionToggle("Titles and Authors", selected: gridStyle == .compact) { gridStyle = .compact }
                optionToggle("Covers Only", selected: gridStyle == .covers) { gridStyle = .covers }
            }
        } label: {
            Image(systemName: "line.3.horizontal.decrease")
        }
        .menuIndicator(.hidden)
        .help("Sort, group, and view options")
    }

    /// A Toggle gets native menu checkmark treatment. The setter only handles
    /// turning an option on because each group is mutually exclusive.
    private func optionToggle(_ title: String, selected: Bool,
                              action: @escaping () -> Void) -> some View {
        Toggle(title, isOn: Binding(get: { selected }, set: { if $0 { action() } }))
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
    }

    private var emptyState: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 48)

            Image(systemName: "books.vertical.fill")
                .font(.system(size: 60))
                .foregroundStyle(Theme.text)
                .padding(.bottom, 28)

            Text("Add Books to Your Library")
                .font(.system(size: 32, weight: .bold))
                .foregroundStyle(Theme.text)
                .multilineTextAlignment(.center)

            Text("Import your EPUB collection and keep all your books in one place.")
                .font(.title3)
                .foregroundStyle(Theme.subtle)
                .multilineTextAlignment(.center)
                .padding(.top, 14)

            Button("Import Books") { importing = true }
                .keyboardShortcut("o", modifiers: .command)
                .buttonStyle(.bordered)
                .controlSize(.large)
                .padding(.top, 28)

            Spacer(minLength: 48)
        }
        .padding(.horizontal, 40)
        .frame(maxWidth: .infinity, minHeight: 440)
    }
}

/// Global reader state and device actions live in a dedicated toolbar item.
/// Book-level send/remove controls remain in DetailView, where their context is.
struct ReaderToolbarMenu: View {
    let devices: [Device]
    var scanning = false
    var scanDone = 0
    var scanTotal = 0
    var jobs: [KindleJob] = []
    var failure: String?
    var onDismissFailure: () -> Void = {}

    private var connected: Bool { !devices.isEmpty }
    private var icon: String {
        if failure != nil { return "externaldrive.badge.exclamationmark" }
        if !connected { return "externaldrive" }
        if scanning || !jobs.isEmpty { return "externaldrive.fill" }
        return "externaldrive.fill.badge.checkmark"
    }

    var body: some View {
        Menu {
            if let failure {
                Button(action: onDismissFailure) {
                    Label(failure, systemImage: "exclamationmark.triangle.fill")
                }
                Divider()
            }
            if !jobs.isEmpty {
                let text = jobs.count == 1
                    ? "\(jobs[0].verb) \(jobs[0].title)…"
                    : "\(jobs.count) transfers in progress…"
                Label(text, systemImage: "arrow.left.arrow.right")
                Divider()
            }
            if devices.isEmpty {
                Label("No reader connected", systemImage: "cable.connector.horizontal")
            } else {
                ForEach(devices) { device in
                    Section(device.name) {
                        if scanning {
                            Label("Scanning \(scanDone) of \(scanTotal)…", systemImage: "arrow.triangle.2.circlepath")
                        } else {
                            Label("Connected", systemImage: "checkmark.circle")
                        }
                        Button {
                            // Reveal the documents folder instead of asking
                            // Launch Services to open a sandboxed volume.
                            NSWorkspace.shared.activateFileViewerSelecting([device.documents])
                        } label: {
                            Label("Show in Finder", systemImage: "folder")
                        }
                        Button {
                            try? NSWorkspace.shared.unmountAndEjectDevice(at: device.volume)
                        } label: {
                            Label("Eject", systemImage: "eject")
                        }
                    }
                }
            }
        } label: {
            ZStack {
                Image(systemName: icon)
                if scanning || !jobs.isEmpty {
                    ProgressView()
                        .controlSize(.mini)
                        .scaleEffect(0.55)
                        .offset(x: 8, y: 8)
                }
            }
        }
        .menuIndicator(.hidden)
        .help(!connected ? "No reader connected"
              : scanning ? "Scanning reader: \(scanDone) of \(scanTotal)"
              : !jobs.isEmpty ? "Reader transfer in progress"
              : "Reader connected")
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
