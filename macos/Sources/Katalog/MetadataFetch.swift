import Foundation

/// Metadata pulled from an online source, ready to pre-fill the editor.
/// Every field is optional — the caller fills only what came back.
struct FetchedMetadata: Identifiable {
    let id = UUID()
    var title: String?
    var authors: [String]
    var publisher: String?
    var publishedDate: String?   // "2016" — for disambiguation
    var isbn: String?
    var description: String?
    var coverID: Int?            // Open Library cover id; URLs built per size below
    var workKey: String?         // "/works/OL…W" — used to fetch the description on pick

    var authorLine: String { authors.joined(separator: ", ") }
    var year: String? { publishedDate.map { String($0.prefix(4)) } }

    /// Full-size cover to store on the book.
    var coverURL: URL? { coverURL(size: "L") }
    /// Small cover for the results list (avoids pulling ~12 large images).
    var thumbnailURL: URL? { coverURL(size: "M") }

    private func coverURL(size: String) -> URL? {
        coverID.flatMap { URL(string: "https://covers.openlibrary.org/b/id/\($0)-\(size).jpg") }
    }
}

/// Online metadata lookup via the Open Library search API (free, no key, no quota).
enum MetadataFetch {
    /// Build the starting search query: ISBN when the field is a real ISBN
    /// (not a uuid/urn), else plain title + author words.
    static func initialQuery(isbn: String?, title: String, author: String) -> String {
        if let isbn, let clean = validISBN(isbn) { return "isbn:" + clean }
        return [title, author].map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
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

    /// Run an Open Library search and map up to `limit` results for the picker.
    static func search(query: String, limit: Int = 12) async throws -> [FetchedMetadata] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return [] }
        var comps = URLComponents(string: "https://openlibrary.org/search.json")!
        comps.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "limit", value: String(limit)),
            URLQueryItem(name: "fields", value: "title,author_name,first_publish_year,isbn,cover_i,publisher,key"),
        ]
        let (data, resp) = try await URLSession.shared.data(from: comps.url!)
        try check(resp, data)
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.docs.map { $0.asMetadata }
    }

    /// Fetch a work's description (not present in search results). Best-effort:
    /// returns nil on any failure so a picked result still applies.
    static func description(forWork key: String) async -> String? {
        guard let url = URL(string: "https://openlibrary.org\(key).json") else { return nil }
        guard let (data, _) = try? await URLSession.shared.data(from: url),
              let work = try? JSONDecoder().decode(Work.self, from: data) else { return nil }
        return work.description?.text
    }

    /// Download cover image bytes from a URL.
    static func coverData(from url: URL) async throws -> Data? {
        let (data, resp) = try await URLSession.shared.data(from: url)
        try check(resp, data)
        return data.isEmpty ? nil : data
    }

    /// Turn a non-2xx HTTP response into a thrown error instead of silently
    /// decoding it as "no results" (the bug that hid Google Books' 429 quota).
    private static func check(_ resp: URLResponse, _ data: Data) throws {
        guard let http = resp as? HTTPURLResponse, !(200...299).contains(http.statusCode) else { return }
        let body = String(data: data.prefix(200), encoding: .utf8) ?? ""
        throw NSError(domain: "MetadataFetch", code: http.statusCode,
                      userInfo: [NSLocalizedDescriptionKey: "HTTP \(http.statusCode). \(body)"])
    }
}

// MARK: - Open Library JSON (only the fields we use; the rest is ignored)

private struct SearchResponse: Decodable {
    let docs: [Doc]
}

private struct Doc: Decodable {
    let title: String?
    let author_name: [String]?
    let first_publish_year: Int?
    let isbn: [String]?
    let cover_i: Int?
    let publisher: [String]?
    let key: String?

    var asMetadata: FetchedMetadata {
        FetchedMetadata(
            title: title,
            authors: author_name ?? [],
            publisher: publisher?.first,
            publishedDate: first_publish_year.map(String.init),
            isbn: bestISBN,
            description: nil,   // filled on pick via description(forWork:)
            coverID: cover_i,
            workKey: key
        )
    }

    /// Prefer a 13-digit ISBN, else the first listed.
    private var bestISBN: String? {
        let all = isbn ?? []
        return all.first { $0.count == 13 } ?? all.first
    }
}

private struct Work: Decodable {
    let description: Description?
    /// Open Library descriptions are sometimes a bare string, sometimes {value: …}.
    enum Description: Decodable {
        case text(String)
        case object(value: String)
        init(from decoder: Decoder) throws {
            if let s = try? decoder.singleValueContainer().decode(String.self) {
                self = .text(s)
            } else {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                self = .object(value: try c.decode(String.self, forKey: .value))
            }
        }
        enum CodingKeys: String, CodingKey { case value }
        var text: String {
            switch self { case .text(let s), .object(let s): return s }
        }
    }
}
