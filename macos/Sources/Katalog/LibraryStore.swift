import Foundation
import KatalogCore

// Book is Equatable/Hashable from the core; give it Identifiable for SwiftUI.
extension Book: Identifiable {}

/// Observable wrapper around the Rust core `Library`, plus persisted settings.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []

    /// Where imported epubs are stored. Changing it re-opens the library.
    @Published var booksDir: String {
        didSet {
            UserDefaults.standard.set(booksDir, forKey: "booksDir")
            reopen()
        }
    }
    /// Copy files into the library on import (vs. reference in place).
    @Published var copyOnImport: Bool {
        didSet { UserDefaults.standard.set(copyOnImport, forKey: "copyOnImport") }
    }
    /// Sort copied files into Author/Title folders.
    @Published var keepOrganized: Bool {
        didSet { UserDefaults.standard.set(keepOrganized, forKey: "keepOrganized") }
    }

    private var lib: Library

    /// Library root (Application Support/Katalog). The db lives here always;
    /// only the books folder is user-configurable.
    static let appRoot: URL = {
        let fm = FileManager.default
        return try! fm.url(for: .applicationSupportDirectory, in: .userDomainMask,
                           appropriateFor: nil, create: true)
            .appendingPathComponent("Katalog", isDirectory: true)
    }()

    static var defaultBooksDir: String {
        appRoot.appendingPathComponent("Books", isDirectory: true).path
    }

    private static var dbPath: String {
        appRoot.appendingPathComponent("library.db").path
    }

    init() {
        let d = UserDefaults.standard
        let dir = d.string(forKey: "booksDir") ?? Self.defaultBooksDir
        booksDir = dir
        copyOnImport = d.object(forKey: "copyOnImport") as? Bool ?? true
        keepOrganized = d.object(forKey: "keepOrganized") as? Bool ?? true
        lib = try! Library.open(dbPath: Self.dbPath, booksDir: dir)
        refresh()
    }

    func resetBooksDir() { booksDir = Self.defaultBooksDir }

    private func reopen() {
        lib = try! Library.open(dbPath: Self.dbPath, booksDir: booksDir)
        refresh()
    }

    func refresh() {
        books = (try? lib.list()) ?? []
    }

    /// Import one file. Parsing + copying is seconds of work per book, so it runs
    /// off the main thread; the caller decides when to `refresh()`.
    /// ponytail: `Library` is Sendable (the Rust side is mutex-guarded), so the
    /// detached task can hold it directly.
    private func importOne(_ url: URL) async throws {
        let (lib, copy, organize) = (self.lib, copyOnImport, keepOrganized)
        try await Task.detached(priority: .userInitiated) {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            _ = try lib.import(epubPath: url.path, copy: copy, organize: organize)
        }.value
    }

    func importBook(_ url: URL) async throws {
        try await importOne(url)
        refresh()
    }

    /// Import files whose duplicate prompt the user already resolved.
    func importAll(_ urls: [URL]) async {
        for url in urls { try? await importOne(url) }
        refresh()  // one list() for the whole batch, not one per book
    }

    /// Flatten a drop/pick selection into epub files, recursing into any
    /// folders. ponytail: app is unsandboxed, so no security-scoped access is
    /// needed to enumerate a dropped/picked directory.
    func epubURLs(from urls: [URL]) -> [URL] {
        let fm = FileManager.default
        return urls.flatMap { url -> [URL] in
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return [] }
            if isDir.boolValue {
                let children = fm.enumerator(at: url, includingPropertiesForKeys: nil)?
                    .allObjects as? [URL] ?? []
                return children.filter { $0.pathExtension.lowercased() == "epub" }
            }
            return url.pathExtension.lowercased() == "epub" ? [url] : []
        }
    }

    /// Import a batch: files with no match are imported immediately; files that
    /// match an existing book come back as prompts for the user to resolve.
    /// One core call for the whole batch — it parses each epub once and builds
    /// the match index once, instead of a parse-and-scan per file per phase.
    func importBatch(_ urls: [URL]) async -> [DuplicatePrompt] {
        let (lib, copy, organize) = (self.lib, copyOnImport, keepOrganized)
        let hits = await Task.detached(priority: .userInitiated) { () -> [DuplicateHit?] in
            let scoped = urls.filter { $0.startAccessingSecurityScopedResource() }
            defer { scoped.forEach { $0.stopAccessingSecurityScopedResource() } }
            return (try? lib.importBatch(epubPaths: urls.map(\.path), copy: copy,
                                         organize: organize)) ?? []
        }.value
        refresh()  // one list() for the whole batch, not one per book
        return zip(urls, hits).compactMap { url, hit in hit.map { DuplicatePrompt(url: url, hit: $0) } }
    }

    func remove(_ book: Book) {
        try? lib.remove(id: book.id)
        refresh()
    }

    /// Apply edited metadata (index + epub file + optional cover). Throws the
    /// core's error so the caller can show why it failed.
    func update(_ book: Book, _ edit: BookEdit) throws -> Book {
        let updated = try lib.update(id: book.id, edit: edit)
        refresh()
        return updated
    }

    func cachePageCount(_ book: Book) throws -> Book {
        let updated = try lib.cachePageCount(id: book.id)
        if let i = books.firstIndex(where: { $0.id == book.id }) { books[i] = updated }
        return updated
    }

    /// Absolute path of the managed epub, validated for transfer.
    func transferPath(_ book: Book) throws -> String {
        try lib.prepareTransfer(id: book.id)
    }
}
