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
        VStack(alignment: .leading, spacing: Theme.spacing) {
            HStack(alignment: .top, spacing: Theme.spacing) {
                CoverImage(path: book.coverPath)
                    .frame(width: 150, height: 225)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radius))

                VStack(alignment: .leading, spacing: 8) {
                    Text(book.title).font(.title2.bold()).foregroundStyle(Theme.text)
                    Text(book.authors.joined(separator: ", ")).foregroundStyle(Theme.subtle)
                    if let lang = book.language {
                        Label(lang, systemImage: "globe").font(.caption).foregroundStyle(Theme.subtle)
                    }
                    if let isbn = book.isbn {
                        Text(isbn).font(.caption).foregroundStyle(Theme.subtle).textSelection(.enabled)
                    }
                    Spacer()
                }
                Spacer()
            }

            if let desc = book.description, !desc.isEmpty {
                ScrollView {
                    Text(desc).foregroundStyle(Theme.text)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 100)
            }

            Divider().overlay(Theme.subtle.opacity(0.3))

            transferSection

            if let status {
                Text(status).font(.caption).foregroundStyle(Theme.subtle)
            }

            Spacer()

            HStack {
                Button(role: .destructive) {
                    store.remove(book); dismiss()
                } label: { Label("Remove", systemImage: "trash") }
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.spacing * 1.5)
        .frame(width: 520, height: 480)
        .background(Theme.bg)
    }

    @ViewBuilder private var transferSection: some View {
        if kindle.devices.isEmpty {
            Label("Connect a Kindle to transfer", systemImage: "cable.connector.horizontal")
                .foregroundStyle(Theme.subtle)
        } else {
            ForEach(kindle.devices) { dev in
                if kindle.onDevice(book) {
                    Label("On \(dev.name)", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.accent)
                } else {
                    Button { send(to: dev) } label: {
                        Label(working ? "Converting…" : "Send to \(dev.name)",
                              systemImage: "arrow.right.circle.fill")
                    }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
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
