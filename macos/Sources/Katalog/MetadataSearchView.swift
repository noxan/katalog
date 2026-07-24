import SwiftUI

/// Online metadata search sheet: an editable query, a list of Open Library
/// results with covers, and a pick that hands the chosen result back to the
/// editor. Opens pre-filled and auto-runs the first search.
struct MetadataSearchView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var query: String
    var onPick: (FetchedMetadata) -> Void

    @State private var results: [FetchedMetadata] = []
    @State private var searching = false
    @State private var error: String?

    init(query: String, onPick: @escaping (FetchedMetadata) -> Void) {
        _query = State(initialValue: query)
        self.onPick = onPick
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacing) {
            Text("Search Online Metadata").font(.title2).fontWeight(.semibold)

            HStack {
                TextField("Title, author, or isbn:9780…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await runSearch() } }
                Button("Search") { Task { await runSearch() } }
                    .keyboardShortcut(.defaultAction)
                    .disabled(searching || query.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            resultsBody

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }
        .padding(Theme.spacing * 1.4)
        .frame(width: 560, height: 520)
        .task { await runSearch() }   // auto-run once on open with the pre-filled query
    }

    @ViewBuilder
    private var resultsBody: some View {
        if searching {
            Spacer(); HStack { Spacer(); ProgressView(); Spacer() }; Spacer()
        } else if let error {
            Spacer(); Text(error).foregroundStyle(.red).frame(maxWidth: .infinity); Spacer()
        } else if results.isEmpty {
            Spacer()
            Text("No results.").foregroundStyle(Theme.subtle).frame(maxWidth: .infinity)
            Spacer()
        } else {
            List(results) { result in
                resultRow(result)
                    .contentShape(Rectangle())
                    .onTapGesture { onPick(result); dismiss() }
            }
            .listStyle(.plain)
        }
    }

    private func resultRow(_ r: FetchedMetadata) -> some View {
        HStack(alignment: .top, spacing: 12) {
            AsyncImage(url: r.thumbnailURL) { image in
                image.resizable().aspectRatio(contentMode: .fit)
            } placeholder: {
                RoundedRectangle(cornerRadius: 3).fill(Theme.surface)
            }
            .frame(width: 40, height: 60)
            .clipShape(RoundedRectangle(cornerRadius: 3))

            VStack(alignment: .leading, spacing: 2) {
                Text(r.title ?? "Untitled").fontWeight(.medium).lineLimit(2)
                if !r.authors.isEmpty {
                    Text(r.authorLine).font(.callout).foregroundStyle(Theme.subtle).lineLimit(1)
                }
                Text([r.year, r.publisher].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(Theme.subtle).lineLimit(1)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func runSearch() async {
        searching = true
        error = nil
        defer { searching = false }
        do {
            results = try await MetadataFetch.search(query: query)
            // Empty is shown by the results.isEmpty branch (gray), not as an error.
        } catch {
            self.error = "Search failed: \(error.localizedDescription)"
        }
    }
}
