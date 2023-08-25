use std::string::FromUtf8Error;

use fast_xml::{events::Event, Reader};

#[derive(Debug)]
pub struct XMLNode {
    name: String,
}

pub struct XMLReader {}

impl XMLReader {
    pub fn parse(content: &[u8]) -> Result<Option<XMLNode>, FromUtf8Error> {
        let mut reader = Reader::from_bytes(content);
        let mut buf = Vec::new();

        let mut root: Option<XMLNode> = None;

        Ok(loop {
            match reader.read_event(&mut buf) {
                Ok(Event::Start(ref e)) => {
                    let node = XMLNode {
                        name: String::from_utf8(e.name().to_vec())?,
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
                Ok(Event::Eof) => break root,
                _ => (),
            }
            buf.clear();
        })
    }
}

#[cfg(test)]
mod tests {
    use crate::xml::XMLReader;

    #[test]
    fn read_xml_test() {
        let xml =
            r#"<tag1 att1 = "test"><tag2><!--Test comment-->Test</tag2><tag2>Test 2</tag2></tag1>"#;
        let xml = XMLReader::parse(xml.as_bytes()).unwrap().unwrap();
        println!("XML: {:?}", xml);

        assert_eq!(xml.name, "tag1");
    }
}
