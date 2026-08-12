import AppKit
import SwiftUI
import KatalogCore

private struct CurrentBookKey: FocusedValueKey {
    typealias Value = Book
}

extension FocusedValues {
    var currentBook: Book? {
        get { self[CurrentBookKey.self] }
        set { self[CurrentBookKey.self] = newValue }
    }
}

extension Notification.Name {
    static let importBooks = Notification.Name("Katalog.importBooks")
    static let editCurrentBook = Notification.Name("Katalog.editCurrentBook")
    static let revealCurrentBook = Notification.Name("Katalog.revealCurrentBook")
    static let removeCurrentBook = Notification.Name("Katalog.removeCurrentBook")
}

private struct BookCommands: Commands {
    @FocusedValue(\.currentBook) private var book

    var body: some Commands {
        CommandMenu("Book") {
            Button { post(.editCurrentBook) } label: {
                Label("Edit Metadata…", systemImage: "pencil")
            }
            .keyboardShortcut("e", modifiers: .command)
            .disabled(book == nil)
            Button { post(.revealCurrentBook) } label: {
                Label("Show in Finder", systemImage: "folder")
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(book == nil)
            Divider()
            Button { post(.removeCurrentBook) } label: {
                Label("Remove…", systemImage: "trash")
            }
            .keyboardShortcut(.delete, modifiers: .command)
            .disabled(book == nil)
        }
    }

    private func post(_ name: Notification.Name) {
        NotificationCenter.default.post(name: name, object: nil)
    }
}

@main
struct KatalogApp: App {
    @StateObject private var store = LibraryStore()
    @StateObject private var kindle = KindleWatcher()

    init() {
        // Needed so a SwiftPM-built executable shows a real window + menu bar.
        NSApplication.shared.setActivationPolicy(.regular)
    }

    var body: some Scene {
        WindowGroup {
            NavigationStack {
                ContentView()
                    .environmentObject(store)
                    .environmentObject(kindle)
            }
            .frame(minWidth: 720, minHeight: 480)
        }
        .commands {
            CommandGroup(after: .newItem) {
                Button { NotificationCenter.default.post(name: .importBooks, object: nil) } label: {
                    Label("Import…", systemImage: "plus")
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            BookCommands()
        }

        // Native Settings scene: adds the "Settings…" menu item and ⌘,.
        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
