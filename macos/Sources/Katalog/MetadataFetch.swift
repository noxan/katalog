import Foundation

/// Metadata pulled from an online source, ready to pre-fill the editor.
/// Every field is optional — the caller fills only what came back.
struct FetchedMetadata {
    var title: String?
    var authors: [String]
    var publisher: String?
    var isbn: String?
    var description: String?
    var coverURL: URL?
}

/// Online metadata lookup via the Google Books volumes API (no key required).
enum MetadataFetch {
    /// Look up a book, preferring ISBN. If an ISBN is given but returns no
    /// match (stale/wrong ISBN), fall back to title + author. Returns the first
    /// match, or nil if nothing was found either way.
    static func lookup(isbn: String?, title: String, author: String) async throws -> FetchedMetadata? {
        let trimmedISBN = isbn?.trimmingCharacters(in: .whitespaces) ?? ""
        if !trimmedISBN.isEmpty, let hit = try await search(query: "isbn:" + trimmedISBN) {
            return hit
        }
        var q = "intitle:" + title
        if !author.trimmingCharacters(in: .whitespaces).isEmpty { q += "+inauthor:" + author }
        return try await search(query: q)
    }

    /// Run one Google Books query and map the first result.
    private static func search(query: String) async throws -> FetchedMetadata? {
        var comps = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")!
        comps.queryItems = [URLQueryItem(name: "q", value: query),
                            URLQueryItem(name: "maxResults", value: "1")]
        guard let url = comps.url else { return nil }

        let (data, _) = try await URLSession.shared.data(from: url)
        let resp = try JSONDecoder().decode(VolumesResponse.self, from: data)
        // ponytail: take items[0] only — no result picker in the MVP.
        guard let info = resp.items?.first?.volumeInfo else { return nil }

        return FetchedMetadata(
            title: info.title,
            authors: info.authors ?? [],
            publisher: info.publisher,
            isbn: info.bestISBN,
            description: info.description,
            coverURL: info.imageLinks?.bestCoverURL
        )
    }

    /// Download cover image bytes from a thumbnail URL.
    static func coverData(from url: URL) async throws -> Data? {
        let (data, _) = try await URLSession.shared.data(from: url)
        return data.isEmpty ? nil : data
    }
}

// MARK: - Google Books JSON (only the fields we use; the rest is ignored)

private struct VolumesResponse: Decodable {
    let items: [Item]?
    struct Item: Decodable { let volumeInfo: VolumeInfo }
}

private struct VolumeInfo: Decodable {
    let title: String?
    let authors: [String]?
    let publisher: String?
    let description: String?
    let industryIdentifiers: [Identifier]?
    let imageLinks: ImageLinks?

    struct Identifier: Decodable { let type: String; let identifier: String }

    /// Prefer ISBN_13, fall back to ISBN_10.
    var bestISBN: String? {
        let ids = industryIdentifiers ?? []
        return ids.first { $0.type == "ISBN_13" }?.identifier
            ?? ids.first { $0.type == "ISBN_10" }?.identifier
    }
}

private struct ImageLinks: Decodable {
    let thumbnail: String?
    let smallThumbnail: String?

    /// Upgrade to https and drop the page-curl overlay for a clean cover.
    var bestCoverURL: URL? {
        guard let raw = thumbnail ?? smallThumbnail else { return nil }
        let cleaned = raw
            .replacingOccurrences(of: "http://", with: "https://")
            .replacingOccurrences(of: "&edge=curl", with: "")
        return URL(string: cleaned)
    }
}
