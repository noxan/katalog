use std::fs::File;

use thiserror::Error;
use zip::{result::ZipError, ZipArchive};

#[derive(Error, Debug)]
pub enum BookError {
    #[error("I/O Error: {0}")]
    IOError(#[from] std::io::Error),
    #[error("Zip Error: {0}")]
    ZipError(#[from] ZipError),
}

fn edit(filepath: &str) -> Result<(), BookError> {
    let reader = File::open(filepath)?;
    let mut archive = ZipArchive::new(reader)?;

    let root_file = archive.by_name("META-INF/container.xml")?;

    Ok(())
}
