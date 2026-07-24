import SwiftUI
import AppKit
import KatalogCore

struct DetailView: View {
    @State private var book: Book
    @EnvironmentObject var store: LibraryStore

    init(book: Book) { _book = State(initialValue: book) }
    @EnvironmentObject var kindle: KindleWatcher
    @Environment(\.dismiss) private var dismiss
    @State private var status: String?
    @State private var hoverSide = 0   // -1 left, 1 right, 0 none

    var body: some View {
        ZStack {
            // Ambient backdrop: the book's own cover, blurred — the only color in the room.
            CoverImage(path: book.coverPath)
                .frame(width: 560, height: 500)
                .clipped()
                .blur(radius: 70)
                .opacity(0.9)
            // ponytail: a nil cover just blurs the neutral placeholder — a soft wash, no branch needed.

            // One calm frosted surface the content sits directly on. Replaces per-section boxes.
            Rectangle().fill(.regularMaterial)

            content
        }
        .frame(width: 560, height: 500)
        .overlay(alignment: .leading) { navButton(-1) }
        .overlay(alignment: .trailing) { navButton(1) }
        .overlay(alignment: .topTrailing) { chrome }
        .contextMenu { menuItems }
        .onChange(of: book.id) { status = nil }
    }

    private var content: some View {
        #if DEBUG
        _ = DescriptionHTMLCheck.run
        #endif
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: Theme.spacing) {
                leftColumn
                rightColumn
            }

            if let desc = book.description, !desc.isEmpty {
                ScrollView {
                    Text(renderedDescription(desc)).font(.callout).lineSpacing(2).foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 160)
            }

            if let status {
                Text(status).font(.caption).foregroundStyle(Theme.subtle)
            }

            Spacer(minLength: 0)
        }
        .padding(Theme.spacing * 1.6)
    }

    // MARK: Left — cover + primary action

    private var leftColumn: some View {
        CoverImage(path: book.coverPath, title: book.title,
                   authors: book.authors.joined(separator: ", "))
            .frame(width: Theme.coverWidth, height: Theme.coverHeight)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            .shadow(color: .black.opacity(0.5), radius: 18, y: 12)
    }

    // MARK: Right — title + aligned metadata

    private var rightColumn: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(book.title)
                .font(.title2).fontWeight(.semibold).tracking(-0.3)
                .foregroundStyle(Theme.text)
            Text(book.authors.joined(separator: ", "))
                .font(.body).foregroundStyle(Theme.subtle)

            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 10) {
                ForEach(metadataRows, id: \.0) { label, value in
                    GridRow {
                        Text(label).foregroundStyle(Theme.subtle)
                        Text(value).foregroundStyle(Theme.text).textSelection(.enabled)
                    }
                }
            }
            .font(.subheadline)
            .padding(.top, 16)

            transferSection.padding(.top, 16)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Present metadata fields, skipping any that are absent — nil-filtering lives here only.
    private var metadataRows: [(String, String)] {
        var rows: [(String, String)] = []
        if let s = book.series, !s.isEmpty { rows.append(("Series", s)) }
        if let p = book.publisher, !p.isEmpty { rows.append(("Publisher", p)) }
        rows.append(("Format", book.format.uppercased()))
        if let l = book.language, !l.isEmpty { rows.append(("Language", l)) }
        if let i = book.isbn, !i.isEmpty { rows.append(("ISBN", i)) }
        rows.append(("Added", formattedAdded))
        return rows
    }

    private static let isoParser = ISO8601DateFormatter()
    private static let dateDisplay: DateFormatter = {
        let f = DateFormatter(); f.dateStyle = .medium; return f
    }()
    private var formattedAdded: String {
        // ponytail: unknown ISO variant → show the raw string rather than hide the row.
        if let d = Self.isoParser.date(from: book.addedAt) { return Self.dateDisplay.string(from: d) }
        return book.addedAt
    }

    // MARK: Chrome — close + overflow menu

    /// Position of the shown book in the library grid's order.
    private var index: Int? { store.books.firstIndex { $0.id == book.id } }

    private func step(_ delta: Int) {
        guard let i = index, store.books.indices.contains(i + delta) else { return }
        book = store.books[i + delta]
    }

    /// Prev/next book, docked to the dialog's left (-1) and right (1) edges.
    private func navButton(_ delta: Int) -> some View {
        let disabled = delta < 0 ? (index ?? 0) <= 0
                                 : index.map { $0 >= store.books.count - 1 } ?? true
        return Button { step(delta) } label: {
            Image(systemName: delta < 0 ? "chevron.backward.circle.fill" : "chevron.forward.circle.fill")
        }
        .buttonStyle(.plain)
        .font(.largeTitle)
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(.secondary)
        .keyboardShortcut(delta < 0 ? .leftArrow : .rightArrow, modifiers: [])
        .disabled(disabled)
        .help(delta < 0 ? "Previous book" : "Next book")
        .padding(Theme.spacing)
        .frame(maxHeight: .infinity)   // tall hover strip along the edge
        .contentShape(Rectangle())
        .opacity(hoverSide == delta ? 1 : 0)
        .animation(.easeInOut(duration: 0.15), value: hoverSide)
        .onHover { hoverSide = $0 ? delta : 0 }
    }

    private var chrome: some View {
        HStack(spacing: 12) {
            Menu {
                menuItems
            } label: {
                Image(systemName: "ellipsis.circle.fill")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()

            Button { dismiss() } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .font(.title2)
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(.secondary)
        .padding(Theme.spacing)
    }

    @ViewBuilder private var menuItems: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: book.filePath)])
        } label: {
            Label("Open in Finder", systemImage: "folder")
        }
        Divider()
        Button(role: .destructive) {
            store.remove(book); dismiss()
        } label: {
            Label("Remove from Library", systemImage: "trash")
        }
    }

    // MARK: Transfer

    @ViewBuilder private var transferSection: some View {
        if kindle.devices.isEmpty {
            Label("Connect a Kindle to transfer", systemImage: "cable.connector.horizontal")
                .font(.caption).foregroundStyle(Theme.subtle)
                .multilineTextAlignment(.center)
        } else {
            let working = kindle.busy(book)
            ForEach(kindle.devices) { dev in
                if kindle.onDevice(book) {
                    // Present/settled state: secondary bordered button, accent
                    // checkmark. The menu chevron keeps it reading as interactive.
                    Menu {
                        Button(role: .destructive) { remove(from: dev) } label: {
                            Label("Remove from \(dev.name)", systemImage: "trash")
                        }
                    } label: {
                        // Explicit HStack: a Menu's `.button` style collapses
                        // Label's icon/title spacing, so it wouldn't match the
                        // Send button. 6pt mirrors Label's default.
                        HStack(spacing: 6) {
                            if working { ProgressView().controlSize(.small) }
                            else { Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.accent) }
                            Text(working ? "Removing…" : "On \(dev.name)")
                        }
                    }
                    .menuStyle(.button)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .fixedSize()
                    .disabled(working)
                } else if kindle.scanning {
                    // Keys aren't in yet — the book may already be on the device,
                    // so don't imply it isn't with a Send button.
                    Label {
                        Text("Checking \(dev.name)…")
                    } icon: { ProgressView().controlSize(.small) }
                        .font(.subheadline).foregroundStyle(Theme.subtle)
                } else {
                    // Primary call-to-action: filled accent button, same height.
                    Button { send(to: dev) } label: {
                        Label {
                            Text(working ? "Converting…" : "Send to \(dev.name)")
                        } icon: {
                            if working { ProgressView().controlSize(.small) }
                            else { Image(systemName: "arrow.right.circle.fill") }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .tint(Theme.accent)
                    .fixedSize()
                    .disabled(working)
                }
            }
        }
    }

    /// Hand off to the watcher, which owns the work so it keeps running (and
    /// stays visible in the status bar) after this page closes.
    private func remove(from device: Device) { kindle.remove(book, from: device) }

    private func send(to device: Device) {
        do { kindle.send(book, epubPath: try store.transferPath(book), to: device) }
        catch { status = "Failed: \(error.localizedDescription)" }
    }
}
