use std::{fs::File, io::Read};

use thiserror::Error;
use zip::{result::ZipError, ZipArchive};

use crate::xml::XMLReader;

#[derive(Error, Debug)]
pub enum BookError {
    #[error("I/O Error: {0}")]
    IOError(#[from] std::io::Error),
    #[error("Zip Error: {0}")]
    ZipError(#[from] ZipError),
    #[error("Attribute not found: {0}")]
    AttributeNotFound(String),
}

pub fn read_file_from_archive(
    mut archive: ZipArchive<File>,
    filename: &str,
) -> Result<Vec<u8>, ZipError> {
    let mut zipfile = archive.by_name(filename)?;

    let mut buf = Vec::<u8>::new();
    zipfile.read_to_end(&mut buf);

    Ok(buf)
}

pub fn find_root_file(archive: ZipArchive<File>) -> Result<String, BookError> {
    let root_file = read_file_from_archive(archive, "META-INF/container.xml")?;
    let root = XMLReader::parse(&root_file).unwrap();
    let root2 = root.borrow();
    let element = root2
        .find("rootfile")
        .ok_or_else(|| BookError::AttributeNotFound("rootfile".into()))?;
    let element2 = element.borrow();
    let path = element2
        .attributes
        .get("full-path")
        .ok_or_else(|| BookError::AttributeNotFound("full-path".into()))?;

    Ok(path.clone())
}

// fn get_container_file(&mut archive: ZipArchive<File>) {}

fn edit(filepath: &str) -> Result<(), BookError> {
    let reader = File::open(filepath)?;
    let mut archive: ZipArchive<File> = ZipArchive::new(reader)?;

    let root_file = archive.by_name("META-INF/container.xml")?;

    Ok(())
}

#[cfg(test)]
mod tests {
    use std::fs::File;

    use zip::ZipArchive;

    use super::find_root_file;

    #[test]
    fn test_find_root_file() {
        let filepath = "/Users/richard/Downloads/Books Project Gutenberg/pg4085-images-3.epub";

        let reader = File::open(filepath).unwrap();
        let archive: ZipArchive<File> = ZipArchive::new(reader).unwrap();

        let root_file = find_root_file(archive).unwrap();

        assert_eq!(root_file, "OEBPS/content.opf");
    }
}
