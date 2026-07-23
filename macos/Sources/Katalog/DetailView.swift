import SwiftUI
import KatalogCore

struct DetailView: View {
    let book: Book
    @EnvironmentObject var store: LibraryStore
    @EnvironmentObject var kindle: KindleWatcher
    @Environment(\.dismiss) private var dismiss
    @State private var status: String?
    @State private var working = false

    var body: some View {
        ZStack {
            // Ambient backdrop: the book's own cover, blurred — the only color in the room.
            CoverImage(path: book.coverPath)
                .frame(width: 560, height: 560)
                .clipped()
                .blur(radius: 70)
                .opacity(0.9)
            // ponytail: a nil cover just blurs the neutral placeholder — a soft wash, no branch needed.

            // One calm frosted surface the content sits directly on. Replaces per-section boxes.
            Rectangle().fill(.regularMaterial)

            content
        }
        .frame(width: 560, height: 560)
        .overlay(alignment: .topTrailing) { chrome }
        .contextMenu { removeButton }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            HStack(alignment: .top, spacing: Theme.spacing) {
                leftColumn
                rightColumn
            }

            if let desc = book.description, !desc.isEmpty {
                Divider().overlay(Theme.subtle.opacity(0.12))
                ScrollView {
                    Text(desc).font(.callout).lineSpacing(2).foregroundStyle(Theme.text)
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
        VStack(spacing: 14) {
            CoverImage(path: book.coverPath)
                .frame(width: Theme.coverWidth, height: Theme.coverHeight)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
                .shadow(color: .black.opacity(0.5), radius: 18, y: 12)

            transferSection.frame(width: Theme.coverWidth)
        }
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

    private var chrome: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 8) {
                Menu {
                    removeButton
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.button)
                .menuIndicator(.hidden)
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)

                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.glass)
                .buttonBorderShape(.circle)
                .keyboardShortcut(.cancelAction)
            }
        }
        .padding(Theme.spacing)
    }

    @ViewBuilder private var removeButton: some View {
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
            ForEach(kindle.devices) { dev in
                if kindle.onDevice(book) {
                    Label("On \(dev.name)", systemImage: "checkmark.circle.fill")
                        .font(.subheadline).foregroundStyle(Theme.accent)
                } else {
                    Button { send(to: dev) } label: {
                        Label(working ? "Converting…" : "Send to \(dev.name)",
                              systemImage: "arrow.right.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.glassProminent).tint(Theme.accent)
                    .disabled(working)
                }
            }
        }
    }

    /// Convert the epub to MOBI (off the main thread — it's CPU work) and copy
    /// the result to the reader.
    private func send(to device: Device) {
        let epubPath: String
        do { epubPath = try store.transferPath(book) }
        catch { status = "Failed: \(error.localizedDescription)"; return }

        working = true
        status = "Converting…"
        Task.detached {
            do {
                let tmp = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .appendingPathExtension("mobi")
                try convertEpubToMobi(epubPath: epubPath, outPath: tmp.path)
                try await MainActor.run { try kindle.transfer(book, from: tmp.path, to: device) }
                try? FileManager.default.removeItem(at: tmp)
                await MainActor.run { status = "Sent to \(device.name) ✓"; working = false }
            } catch {
                await MainActor.run { status = "Failed: \(error.localizedDescription)"; working = false }
            }
        }
    }
}
