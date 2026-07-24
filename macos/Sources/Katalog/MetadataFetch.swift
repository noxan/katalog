import Foundation

/// Metadata pulled from an online source, ready to pre-fill the editor.
/// Every field is optional — the caller fills only what came back.
struct FetchedMetadata: Identifiable {
    let id = UUID()
    var title: String?
    var authors: [String]
    var publisher: String?
    var publishedDate: String?   // "2016" or "2016-05-01" — for disambiguation
    var isbn: String?
    var description: String?
    var coverURL: URL?

    var authorLine: String { authors.joined(separator: ", ") }
    var year: String? { publishedDate.map { String($0.prefix(4)) } }
}

/// Online metadata lookup via the Google Books volumes API (no key required).
enum MetadataFetch {
    /// Build the search query for a book: ISBN when the field is a real ISBN
    /// (not a uuid/urn), else title + author.
    static func initialQuery(isbn: String?, title: String, author: String) -> String {
        if let isbn, let clean = validISBN(isbn) { return "isbn:" + clean }
        var q = "intitle:" + title
        if !author.trimmingCharacters(in: .whitespaces).isEmpty { q += "+inauthor:" + author }
        return q
    }

    /// Normalized ISBN if `raw` is shaped like an ISBN-10/13, else nil.
    /// ponytail: shape check, not checksum — enough to reject uuid/urn values.
    static func validISBN(_ raw: String) -> String? {
        let d = raw.filter { !$0.isWhitespace && $0 != "-" }
        let isDigits = { (s: Substring) in s.allSatisfy(\.isNumber) }
        switch d.count {
        case 13 where isDigits(d[...]): return d
        case 10 where isDigits(d.dropLast()) && (d.last!.isNumber || d.last! == "X" || d.last! == "x"): return d
        default: return nil
        }
    }

    /// Run a Google Books query and map up to `limit` results for the picker.
    static func search(query: String, limit: Int = 12) async throws -> [FetchedMetadata] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        var comps = URLComponents(string: "https://www.googleapis.com/books/v1/volumes")!
        comps.queryItems = [URLQueryItem(name: "q", value: trimmed),
                            URLQueryItem(name: "maxResults", value: String(limit))]
        guard let url = comps.url else { return [] }

        let (data, _) = try await URLSession.shared.data(from: url)
        let resp = try JSONDecoder().decode(VolumesResponse.self, from: data)
        return (resp.items ?? []).map { item in
            let info = item.volumeInfo
            return FetchedMetadata(
                title: info.title,
                authors: info.authors ?? [],
                publisher: info.publisher,
                publishedDate: info.publishedDate,
                isbn: info.bestISBN,
                description: info.description,
                coverURL: info.imageLinks?.bestCoverURL
            )
        }
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
    let publishedDate: String?
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
