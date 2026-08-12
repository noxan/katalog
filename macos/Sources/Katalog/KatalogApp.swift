import AppKit
import SwiftUI

extension Notification.Name {
    static let importBooks = Notification.Name("Katalog.importBooks")
    static let editCurrentBook = Notification.Name("Katalog.editCurrentBook")
    static let revealCurrentBook = Notification.Name("Katalog.revealCurrentBook")
    static let removeCurrentBook = Notification.Name("Katalog.removeCurrentBook")
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
                    Label("Import Books or Folder…", systemImage: "plus")
                }
                .keyboardShortcut("o", modifiers: .command)
            }
            CommandMenu("Book") {
                Button { NotificationCenter.default.post(name: .editCurrentBook, object: nil) } label: {
                    Label("Edit Metadata…", systemImage: "pencil")
                }
                .keyboardShortcut("e", modifiers: .command)
                Button { NotificationCenter.default.post(name: .revealCurrentBook, object: nil) } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .keyboardShortcut("j", modifiers: [.command, .shift])
                Divider()
                Button { NotificationCenter.default.post(name: .removeCurrentBook, object: nil) } label: {
                    Label("Remove from Library", systemImage: "trash")
                }
                .keyboardShortcut(.delete, modifiers: .command)
            }
        }

        // Native Settings scene: adds the "Settings…" menu item and ⌘,.
        Settings {
            SettingsView()
                .environmentObject(store)
        }
    }
}
