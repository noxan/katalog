import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: LibraryStore
    @AppStorage("gridStyle") private var gridStyle: GridStyle = .compact
    @AppStorage("sortOrder") private var sortOrder: SortOrder = .dateAdded
    @AppStorage("grouping") private var grouping: Grouping = .none

    var body: some View {
        Form {
            Section {
                Picker("Grid style", selection: $gridStyle) {
                    Text("Compact").tag(GridStyle.compact)
                    Text("Covers").tag(GridStyle.covers)
                }
                Picker("Sort by", selection: $sortOrder) {
                    ForEach(SortOrder.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                Picker("Grouping", selection: $grouping) {
                    ForEach(Grouping.allCases, id: \.self) { Text($0.label).tag($0) }
                }
            }

            Section {
                LabeledContent("Library Location") {
                    PathControl(path: store.booksDir)
                        .help("Click to open in Finder")
                }
                HStack {
                    Button("Change…") { chooseFolder() }
                    Button("Reset") { store.resetBooksDir() }
                    Spacer()
                }
            }

            Section {
                Toggle("Keep library folder organized", isOn: bind(\.keepOrganized))
                    .disabled(!store.copyOnImport)
                Text("Places files into author and title folders.")
                    .font(.caption).foregroundStyle(.secondary)

                Toggle("Copy files to library when adding", isOn: bind(\.copyOnImport))
                Text("When off, the library references files where they are.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460, height: 300)
        .navigationTitle("Settings")
    }

    // macOS 13 has no @Bindable for ObservableObject; make bindings by hand.
    private func bind(_ key: ReferenceWritableKeyPath<LibraryStore, Bool>) -> Binding<Bool> {
        Binding(get: { store[keyPath: key] }, set: { store[keyPath: key] = $0 })
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Choose"
        panel.directoryURL = URL(fileURLWithPath: store.booksDir)
        if panel.runModal() == .OK, let url = panel.url {
            store.booksDir = url.path
        }
    }
}
