pub mod epub;
pub mod library;
pub mod matching;
pub mod mobi;
pub mod mobi_index;

pub use library::{Book, KatalogError, Library};

uniffi::setup_scaffolding!();
