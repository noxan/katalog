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

    func importBook(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        _ = try lib.import(epubPath: url.path, copy: copyOnImport, organize: keepOrganized)
        refresh()
    }

    func remove(_ book: Book) {
        try? lib.remove(id: book.id)
        refresh()
    }

    /// Absolute path of the managed epub, validated for transfer.
    func transferPath(_ book: Book) throws -> String {
        try lib.prepareTransfer(id: book.id)
    }
}
