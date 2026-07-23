import SwiftUI
import KatalogCore

/// A duplicate awaiting the user's decision.
struct DuplicatePrompt: Identifiable {
    let id = UUID()
    let url: URL
    let hit: DuplicateHit
}

/// Photos-style duplicate prompt: incoming vs. existing, with an option to
/// apply the choice to every remaining duplicate in the batch.
struct DuplicateDialog: View {
    let prompt: DuplicatePrompt
    let remaining: Int
    /// (importAnyway, applyToAll)
    let onResolve: (Bool, Bool) -> Void
    let onCancel: () -> Void

    @State private var applyToAll = false

    var body: some View {
        VStack(spacing: Theme.spacing) {
            Text("Would you like to import the following duplicate item?")
                .font(.title3.bold())
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.text)

            HStack(alignment: .top, spacing: 48) {
                column("Importing", cover: NSImage(data: prompt.hit.incomingCover ?? Data()),
                       title: prompt.hit.incomingTitle, authors: prompt.hit.incomingAuthors)
                column("Existing", cover: prompt.hit.existing.coverPath.flatMap { NSImage(contentsOfFile: $0) },
                       title: prompt.hit.existing.title, authors: prompt.hit.existing.authors)
            }

            if remaining > 1 {
                Toggle("Apply to all duplicates", isOn: $applyToAll)
                    .toggleStyle(.checkbox)
                    .foregroundStyle(Theme.text)
            }

            HStack {
                Button("Cancel") { onCancel() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Don't Import") { onResolve(false, applyToAll) }
                Button("Import") { onResolve(true, applyToAll) }
                    .buttonStyle(.borderedProminent).tint(Theme.accent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(Theme.spacing * 1.5)
        .frame(width: 460)
        .background(Theme.bg)
    }

    private func column(_ label: String, cover: NSImage?, title: String, authors: [String]) -> some View {
        VStack(spacing: 10) {
            Text(label).font(.headline).foregroundStyle(Theme.text)
            Group {
                if let cover {
                    Image(nsImage: cover).resizable().aspectRatio(contentMode: .fit)
                } else {
                    Image(systemName: "book.closed").font(.largeTitle).foregroundStyle(Theme.subtle)
                }
            }
            .frame(width: 120, height: 180)
            .frame(maxWidth: .infinity)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius))
            Text(title).font(.system(size: 13, weight: .medium))
                .foregroundStyle(Theme.text).lineLimit(2).multilineTextAlignment(.center)
            Text(authors.joined(separator: ", ")).font(.system(size: 11))
                .foregroundStyle(Theme.subtle).lineLimit(1)
        }
        .frame(width: 160)
    }
}
