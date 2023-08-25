use std::{cell::RefCell, rc::Rc, string::FromUtf8Error};

use fast_xml::{events::Event, Reader};

#[derive(Debug)]
pub struct XMLNode {
    name: String,
    parent: Option<Rc<RefCell<XMLNode>>>,
    children: Vec<Rc<RefCell<XMLNode>>>,
}

#[derive(Debug, Clone)]
pub enum XMLError {
    FromUtf8Error(FromUtf8Error),
    EmptyRoot,
    InvalidState,
}

pub struct XMLReader {}

fn from_utf8(raw: &[u8]) -> Result<String, XMLError> {
    String::from_utf8(raw.to_vec()).map_err(XMLError::FromUtf8Error)
}

impl XMLReader {
    pub fn parse(content: &[u8]) -> Result<RefCell<XMLNode>, XMLError> {
        let mut reader = Reader::from_bytes(content);
        let mut buf = Vec::new();

        let mut root: Option<Rc<RefCell<XMLNode>>> = None;
        let mut parents: Vec<Rc<RefCell<XMLNode>>> = Vec::new();

        loop {
            match reader.read_event(&mut buf) {
                Ok(Event::Start(ref e)) => {
                    let node = Rc::new(RefCell::new(XMLNode {
                        name: from_utf8(e.name())?,
                        parent: None,
                        children: Vec::new(),
                    }));

                    let current = parents.last();
                    if let Some(c) = current {
                        c.borrow_mut().children.push(node.clone());
                        node.borrow_mut().parent = Some(c.clone());
                    };

                    parents.push(node.clone());

                    if root.is_none() {
                        root = Some(node);
                    }
                }
                Ok(Event::Empty(ref e)) => {}
                Ok(Event::End(ref e)) => {
                    println!("End tag: {}", from_utf8(e.name())?);
                    if !parents.is_empty() {
                        parents.pop();
                    }
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
            Some(root) => match Rc::try_unwrap(root) {
                Ok(node) => Ok(node),
                Err(_) => Err(XMLError::InvalidState),
            },
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
