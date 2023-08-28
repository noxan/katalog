use std::fs::File;

use thiserror::Error;
use zip::ZipArchive;

#[derive(Error, Debug)]
pub enum BookError {
    #[error("I/O Error: {0}")]
    IOError(#[from] std::io::Error),
}

fn edit(filepath: &str) -> Result<(), BookError> {
    let reader = File::open(filepath)?;
    let archive = ZipArchive::new(reader);

    Ok(())
}
