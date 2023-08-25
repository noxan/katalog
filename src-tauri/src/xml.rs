use std::string::FromUtf8Error;

use fast_xml::{events::Event, Reader};

#[derive(Debug)]
pub struct XMLNode {
    name: String,
}

#[derive(Debug, Clone)]
pub enum XMLError {
    FromUtf8Error(FromUtf8Error),
    EmptyRoot,
}

pub struct XMLReader {}

impl XMLReader {
    pub fn parse(content: &[u8]) -> Result<XMLNode, XMLError> {
        let mut reader = Reader::from_bytes(content);
        let mut buf = Vec::new();

        let mut root: Option<XMLNode> = None;

        loop {
            match reader.read_event(&mut buf) {
                Ok(Event::Start(ref e)) => {
                    let node = XMLNode {
                        name: String::from_utf8(e.name().to_vec())
                            .map_err(XMLError::FromUtf8Error)?,
                    };
                    if root.is_none() {
                        root = Some(node);
                    }
                    println!("Start tag: {:?}", String::from_utf8(e.name().to_vec()));
                    for attr in e.attributes() {
                        let attr = attr.unwrap();
                        println!(
                            "attributes: {:?} = {:?}",
                            String::from_utf8(attr.key.to_vec()),
                            String::from_utf8(attr.value.to_vec())
                        );
                    }
                }
                Ok(Event::Empty(ref e)) => {
                    println!("Empty tag: {:?}", String::from_utf8(e.name().to_vec()));
                    for attr in e.attributes() {
                        let attr = attr.unwrap();
                        println!(
                            "attributes: {:?} = {:?}",
                            String::from_utf8(attr.key.to_vec()),
                            String::from_utf8(attr.value.to_vec())
                        );
                    }
                }
                Ok(Event::End(ref e)) => {
                    println!("End tag: {:?}", String::from_utf8(e.name().to_vec()));
                }
                Ok(Event::Text(e)) => {
                    println!("Text: {:?}", e.unescape_and_decode(&reader).unwrap());
                }
                Ok(Event::Eof) => break,
                _ => (),
            }
            buf.clear();
        }

        match root {
            None => return Err(XMLError::EmptyRoot),
            Some(root) => Ok(root),
        }
    }
}

#[cfg(test)]
mod tests {
    use crate::xml::XMLReader;

    #[test]
    fn read_xml_test() {
        let xml =
            r#"<tag1 att1 = "test"><tag2><!--Test comment-->Test</tag2><tag2>Test 2</tag2></tag1>"#;
        let xml = XMLReader::parse(xml.as_bytes()).unwrap();
        println!("XML: {:?}", xml);

        assert_eq!(xml.name, "tag1");
    }
}
