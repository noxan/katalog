use fast_xml::{events::Event, Reader};

pub struct XMLReader {}

impl XMLReader {
    pub fn parse(content: &[u8]) {
        let mut reader = Reader::from_bytes(content);
        let mut buf = Vec::new();

        loop {
            match reader.read_event(&mut buf) {
                Ok(Event::Start(ref e)) => {
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
    }
}

#[cfg(test)]
mod tests {
    use crate::xml::XMLReader;

    #[test]
    fn read_xml_test() {
        let xml =
            r#"<tag1 att1 = "test"><tag2><!--Test comment-->Test</tag2><tag2>Test 2</tag2></tag1>"#;
        XMLReader::parse(xml.as_bytes());

        assert_eq!(2 + 2, 4);
    }
}
