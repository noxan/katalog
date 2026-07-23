import Foundation

// Book descriptions from epub metadata are often a soup of HTML. Render a
// deliberately tiny subset — emphasis, paragraphs, line breaks, list bullets —
// and throw everything else away (unknown tags, broken tags, styling, fonts).
// The result is normalised like Markdown: single spaces, at most one blank line.

/// Sanitised, Markdown-flavoured plain text ready for `AttributedString(markdown:)`.
/// ponytail: regex-level parser, not a real HTML tree — fine for a metadata blurb.
func normalizeDescriptionHTML(_ html: String) -> String {
    var s = html
    let rx: NSString.CompareOptions = [.regularExpression, .caseInsensitive]

    // Escape Markdown metacharacters in the source *before* we inject our own,
    // so literal *, _, ` etc. in the text can't turn into accidental styling.
    for ch in ["\\", "`", "*", "_", "[", "]", "~"] {
        s = s.replacingOccurrences(of: ch, with: "\\" + ch)
    }

    // Kept tags → Markdown / structure. Attribute groups forbid `<` so a
    // malformed, unclosed tag can't gobble following text.
    s = s.replacingOccurrences(of: #"<\s*(b|strong)(\s[^<>]*)?>"#, with: "**", options: rx)
    s = s.replacingOccurrences(of: #"<\s*/\s*(b|strong)\s*>"#, with: "**", options: rx)
    s = s.replacingOccurrences(of: #"<\s*(i|em)(\s[^<>]*)?>"#, with: "*", options: rx)
    s = s.replacingOccurrences(of: #"<\s*/\s*(i|em)\s*>"#, with: "*", options: rx)
    s = s.replacingOccurrences(of: #"<\s*li(\s[^<>]*)?>"#, with: "\n• ", options: rx)
    s = s.replacingOccurrences(of: #"<\s*br\s*/?>"#, with: "\n", options: rx)
    // `</li>` intentionally omitted — the opening `<li>` already starts the line.
    s = s.replacingOccurrences(of: #"<\s*/\s*(p|div|h[1-6]|ul|ol)\s*>"#, with: "\n", options: rx)

    // Drop every remaining tag, then any stray angle brackets from broken ones.
    s = s.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
    s = s.replacingOccurrences(of: #"[<>]"#, with: "", options: .regularExpression)

    s = decodeEntities(s)

    // Normalise whitespace: unix newlines, collapse runs, cap blank lines at one.
    s = s.replacingOccurrences(of: #"\r\n?"#, with: "\n", options: .regularExpression)
    s = s.replacingOccurrences(of: #"[ \t]+"#, with: " ", options: .regularExpression)
    s = s.replacingOccurrences(of: #" *\n *"#, with: "\n", options: .regularExpression)
    s = s.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
    return s.trimmingCharacters(in: .whitespacesAndNewlines)
}

/// Rendered description for SwiftUI `Text`. Falls back to the plain string if
/// Markdown parsing ever chokes.
func renderedDescription(_ html: String) -> AttributedString {
    let text = normalizeDescriptionHTML(html)
    let opts = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return (try? AttributedString(markdown: text, options: opts)) ?? AttributedString(text)
}

/// Decode only the entities that actually turn up in book blurbs.
private func decodeEntities(_ input: String) -> String {
    var s = input
    let named = ["&nbsp;": " ", "&lt;": "<", "&gt;": ">", "&quot;": "\"", "&apos;": "'",
                 "&hellip;": "…", "&mdash;": "—", "&ndash;": "–",
                 "&rsquo;": "\u{2019}", "&lsquo;": "\u{2018}", "&ldquo;": "\u{201C}", "&rdquo;": "\u{201D}"]
    for (k, v) in named { s = s.replacingOccurrences(of: k, with: v) }
    s = decodeNumeric(s, pattern: #"&#(\d+);"#, radix: 10)
    s = decodeNumeric(s, pattern: #"&#[xX]([0-9A-Fa-f]+);"#, radix: 16)
    return s.replacingOccurrences(of: "&amp;", with: "&")  // last, so &amp;lt; survives literally
}

private func decodeNumeric(_ s: String, pattern: String, radix: Int) -> String {
    guard let re = try? Regex(pattern) else { return s }
    return s.replacing(re) { m in
        if let sub = m.output[1].substring, let code = UInt32(sub, radix: radix),
           let scalar = Unicode.Scalar(code) { return String(scalar) }
        return String(m.output[0].substring ?? "")
    }
}

#if DEBUG
// One runnable check for the parser — runs once on first DetailView render.
enum DescriptionHTMLCheck {
    static let run: Void = {
        func n(_ h: String) -> String { normalizeDescriptionHTML(h) }
        assert(n("<p>Hello</p><p>World</p>") == "Hello\nWorld")
        assert(n("a<br/>b") == "a\nb")
        assert(n("Tom &amp; Jerry &mdash; done") == "Tom & Jerry — done")
        assert(n("caf&#233; &#x263A;") == "café ☺")
        assert(n("<b>bold</b> <unknown x=\"y\">plain</unknown>") == "**bold** plain")
        assert(n("<ul><li>one</li><li>two</li></ul>") == "• one\n• two")
        assert(n("a\n\n\n\n\nb") == "a\n\nb")                     // consecutive breaks capped
        assert(n("keep 2*3 and a_b intact") == "keep 2\\*3 and a\\_b intact")  // escaped, not styling
        assert(n("a <x>b</x> <c d=1>e") == "a b e")              // unknown tags discarded
    }()
}
#endif
