import Foundation
import KatalogCore

// Book is Equatable/Hashable from the core; give it Identifiable for SwiftUI.
extension Book: Identifiable {}

/// Observable wrapper around the Rust core `Library`.
@MainActor
final class LibraryStore: ObservableObject {
    @Published private(set) var books: [Book] = []
    private let lib: Library

    init() {
        let fm = FileManager.default
        let root = try! fm.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ).appendingPathComponent("Katalog", isDirectory: true)

        let db = root.appendingPathComponent("library.db").path
        let booksDir = root.appendingPathComponent("Books", isDirectory: true).path
        lib = try! Library.open(dbPath: db, booksDir: booksDir)
        refresh()
    }

    func refresh() {
        books = (try? lib.list()) ?? []
    }

    func importBook(_ url: URL) throws {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        _ = try lib.import(epubPath: url.path)
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
