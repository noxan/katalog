//! Canonical book matching, shared by duplicate detection and device matching.
//!
//! A book yields one or more keys; two books "match" when their key sets
//! intersect. ISBN is the strong signal; a normalized title is the fallback so
//! books also match across formats and filenames that carry no ISBN.

/// Lowercase, keep only alphanumerics (Unicode-aware). Drops spacing,
/// punctuation, and case so titles/ISBNs compare regardless of formatting.
pub fn normalize(s: &str) -> String {
    s.chars()
        .filter(|c| c.is_alphanumeric())
        .flat_map(char::to_lowercase)
        .collect()
}

/// Match keys for a book: its ISBN (if any) and its normalized title.
pub fn keys_for(title: &str, isbn: Option<&str>) -> Vec<String> {
    let mut keys = Vec::new();
    if let Some(isbn) = isbn.map(str::trim).filter(|s| !s.is_empty()) {
        let n = normalize(isbn);
        if !n.is_empty() {
            keys.push(format!("isbn:{n}"));
        }
    }
    let t = normalize(title);
    if !t.is_empty() {
        keys.push(format!("title:{t}"));
    }
    keys
}

/// Whether two key sets share any key.
pub fn shares_key(a: &[String], b: &[String]) -> bool {
    a.iter().any(|k| b.contains(k))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn keys_and_matching() {
        let a = keys_for("The Left Hand of Darkness", Some("urn:isbn:978-0"));
        // ISBN normalizes (punctuation dropped) and title key is present.
        assert!(a.contains(&"isbn:urnisbn9780".to_string()));
        assert!(a.contains(&"title:thelefthandofdarkness".to_string()));

        // Same title, different formatting → matches on the title key.
        let b = keys_for("the left  hand of darkness!", None);
        assert!(shares_key(&a, &b));

        // Unrelated book → no shared key.
        let c = keys_for("Blindsight", None);
        assert!(!shares_key(&a, &c));
    }
}
