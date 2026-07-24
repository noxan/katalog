import SwiftUI
import AppKit
import UniformTypeIdentifiers
import KatalogCore

/// Metadata editor sheet. Text fields plus an Apple Music-style cover well: drag
/// an image file onto the cover to replace it. Returns the updated book to the
/// caller on save.
struct EditView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) private var dismiss

    let book: Book
    /// Called with the saved book so the detail view can refresh in place.
    var onSaved: (Book) -> Void

    @State private var title: String
    @State private var authors: String     // comma-separated
    @State private var series: String
    @State private var seriesIndex: String // series position, parsed to a number on save
    @State private var publisher: String
    @State private var isbn: String
    @State private var language: String
    @State private var descriptionText: String
    @State private var coverData: Data?     // set when a new cover is chosen/dropped/pasted
    @State private var coverImage: NSImage? // decoded once per set, so keystrokes don't re-decode
    @State private var removeCover = false  // set when the cover is removed
    @State private var dropTargeted = false
    @State private var error: String?
    @State private var fetching = false     // applying a picked result (cover download)
    @State private var showingSearch = false

    init(book: Book, onSaved: @escaping (Book) -> Void) {
        self.book = book
        self.onSaved = onSaved
        _title = State(initialValue: book.title)
        _authors = State(initialValue: book.authors.joined(separator: ", "))
        _series = State(initialValue: book.series ?? "")
        _seriesIndex = State(initialValue: book.seriesIndex.map(Self.formatIndex) ?? "")
        _publisher = State(initialValue: book.publisher ?? "")
        _isbn = State(initialValue: book.isbn ?? "")
        _language = State(initialValue: book.language ?? "")
        _descriptionText = State(initialValue: book.description ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            Text("Edit Metadata").font(.title2).fontWeight(.semibold)

            HStack(alignment: .top, spacing: Theme.spacing) {
                coverWell
                fields
            }

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Button {
                    showingSearch = true
                } label: {
                    if fetching {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Search Online", systemImage: "magnifyingglass")
                    }
                }
                .disabled(fetching)
                .help("Search Open Library and pick the right match")
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(Theme.spacing * 1.4)
        .frame(width: 540)
        .sheet(isPresented: $showingSearch) {
            MetadataSearchView(
                query: MetadataFetch.initialQuery(isbn: emptyToNil(isbn), title: title, author: firstAuthor)
            ) { result in
                Task { await apply(result) }
            }
        }
    }

    /// The Authors field split into trimmed, non-empty names.
    private var parsedAuthors: [String] {
        authors.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var firstAuthor: String { parsedAuthors.first ?? "" }

    // MARK: Cover well — drop an image to replace it (Apple Music style)

    private var coverWell: some View {
        ZStack {
            if let coverImage {
                Image(nsImage: coverImage).resizable().aspectRatio(contentMode: .fill)
            } else {
                // removeCover forces the placeholder by hiding the current cover.
                CoverImage(path: removeCover ? nil : book.coverPath, title: book.title,
                           authors: book.authors.joined(separator: ", "))
            }
        }
        .frame(width: Theme.coverWidth, height: Theme.coverHeight)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.radius)
                .strokeBorder(dropTargeted ? Theme.accent : .clear, lineWidth: 3)
        )
        .overlay(alignment: .bottom) {
            Text("Click, drop, or paste")
                .font(.caption2).foregroundStyle(Theme.subtle)
                .padding(4)
                .opacity(dropTargeted ? 1 : 0.55)
        }
        .contentShape(Rectangle())
        .onTapGesture { chooseCover() }
        .focusable()
        .focusEffectDisabled()   // our accent drop border is the focus cue; hide the square system ring
        .onPasteCommand(of: [.image, .fileURL]) { _ in pasteCover() }
        .dropDestination(for: URL.self) { urls, _ in
            guard let url = urls.first, let data = imageData(from: url) else { return false }
            setCover(data)
            return true
        } isTargeted: { dropTargeted = $0 }
        .contextMenu {
            Button("Paste") { pasteCover() }.disabled(!clipboardHasImage)
            Button("Remove", role: .destructive) { clearCover() }
                .disabled(removeCover || (book.coverPath == nil && coverData == nil))
        }
        .help("Click to choose, drag an image here, or paste to replace the cover")
    }

    // MARK: Cover actions

    private func setCover(_ data: Data) {
        coverData = data
        coverImage = NSImage(data: data)
        removeCover = false
    }

    private func clearCover() {
        coverData = nil
        coverImage = nil
        removeCover = true
    }

    /// Validated image bytes from a file URL, or nil if it doesn't decode.
    private func imageData(from url: URL) -> Data? {
        guard let data = try? Data(contentsOf: url), NSImage(data: data) != nil else { return nil }
        return data
    }

    private func chooseCover() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        if panel.runModal() == .OK, let url = panel.url, let data = imageData(from: url) {
            setCover(data)
        }
    }

    private var clipboardHasImage: Bool {
        NSPasteboard.general.canReadObject(forClasses: [NSImage.self], options: nil)
    }

    /// Paste an image from the clipboard — either raw image data or a copied
    /// image file. Normalizes to PNG bytes so the epub manifest type is known.
    private func pasteCover() {
        let pb = NSPasteboard.general
        if let img = NSImage(pasteboard: pb), let png = pngData(img) {
            setCover(png)
        } else if let url = pb.readObjects(forClasses: [NSURL.self], options: nil)?.first as? URL,
                  let data = imageData(from: url) {
            setCover(data)
        }
    }

    private func pngData(_ img: NSImage) -> Data? {
        guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }

    // MARK: Text fields

    private var fields: some View {
        VStack(alignment: .leading, spacing: 10) {
            field("Title", $title)
            field("Authors", $authors, prompt: "comma-separated")
            HStack(alignment: .bottom, spacing: 10) {
                field("Series", $series)
                field("Book #", $seriesIndex, prompt: "e.g. 3").frame(width: 90)
            }
            field("Publisher", $publisher)
            field("ISBN", $isbn)
            field("Language", $language)
            VStack(alignment: .leading, spacing: 4) {
                Text("Description").font(.caption).foregroundStyle(Theme.subtle)
                // ponytail: description edits are plain text; renderedDescription handles non-HTML.
                TextEditor(text: $descriptionText)
                    .font(.callout)
                    .frame(height: 90)
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.subtle.opacity(0.3)))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func field(_ label: String, _ text: Binding<String>, prompt: String = "") -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Theme.subtle)
            TextField(prompt, text: text)
                .textFieldStyle(.roundedBorder)
        }
    }

    // MARK: Online lookup

    /// Apply a result picked in the search sheet. Only non-empty fields
    /// overwrite, so nothing the user typed is lost when the source lacks a value.
    private func apply(_ meta: FetchedMetadata) async {
        if let t = meta.title { title = t }
        if !meta.authors.isEmpty { authors = meta.authors.joined(separator: ", ") }
        if let p = meta.publisher { publisher = p }
        if let i = meta.isbn { isbn = i }
        fetching = true
        defer { fetching = false }

        // Description (from the work record) and cover live at different
        // endpoints — fetch them concurrently.
        async let desc = resolvedDescription(meta)
        async let cover = coverBytes(meta)
        if let d = await desc { descriptionText = d }
        do {
            if let data = try await cover { setCover(data) }
        } catch {
            self.error = "Couldn't download cover: \(error.localizedDescription)"
        }
    }

    /// The description isn't in search results — fetch the work record on pick.
    private func resolvedDescription(_ meta: FetchedMetadata) async -> String? {
        if let d = meta.description { return d }
        guard let key = meta.workKey else { return nil }
        return await MetadataFetch.description(forWork: key)
    }

    private func coverBytes(_ meta: FetchedMetadata) async throws -> Data? {
        guard let url = meta.coverURL else { return nil }
        return try await MetadataFetch.coverData(from: url)
    }

    // MARK: Save

    private func save() {
        let edit = BookEdit(
            title: title.trimmingCharacters(in: .whitespaces),
            authors: parsedAuthors,
            series: emptyToNil(series),
            seriesIndex: Double(seriesIndex.trimmingCharacters(in: .whitespaces)),
            publisher: emptyToNil(publisher),
            isbn: emptyToNil(isbn),
            language: emptyToNil(language),
            description: emptyToNil(descriptionText),
            cover: coverData,
            removeCover: removeCover
        )
        do {
            let saved = try store.update(book, edit)
            onSaved(saved)
            dismiss()
        } catch {
            NSLog("Katalog: save failed for \(book.filePath): \(error)")
            self.error = "Couldn't save: \(error.localizedDescription)"
        }
    }

    /// Show a whole index as "3", a fractional one as "1.5" — no trailing ".0".
    static func formatIndex(_ n: Double) -> String {
        n == n.rounded() ? String(Int(n)) : String(n)
    }

    private func emptyToNil(_ s: String) -> String? {
        let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return t.isEmpty ? nil : t
    }
}
