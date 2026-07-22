import AppKit
import SwiftUI

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
            .preferredColorScheme(.dark)
        }
    }
}
