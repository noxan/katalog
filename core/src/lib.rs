pub mod epub;
pub mod library;

pub use library::{Book, KatalogError, Library};

uniffi::setup_scaffolding!();
