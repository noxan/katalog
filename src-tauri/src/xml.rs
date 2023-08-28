use std::{
    cell::RefCell,
    collections::HashMap,
    rc::{Rc, Weak},
    string::FromUtf8Error,
};

use fast_xml::{
    events::{attributes::Attributes, Event},
    Reader,
};

#[derive(Debug)]
pub struct XMLNode {
    pub name: String,
    pub attributes: HashMap<String, String>,
    parent: Option<Weak<RefCell<XMLNode>>>,
    children: Vec<Rc<RefCell<XMLNode>>>,
}

impl XMLNode {
    pub fn find(&self, tag: &str) -> Option<Rc<RefCell<XMLNode>>> {
        for child in &self.children {
            let node = child.borrow();
            if node.name == tag {
                return Some(child.clone());
            } else if let Some(next) = node.find(tag) {
                return Some(next);
            }
        }
        None
    }
}

#[derive(Debug, Clone)]
pub enum XMLError {
    FromUtf8Error(FromUtf8Error),
    EmptyRoot,
    InvalidState,
}

pub struct XMLReader;

fn from_utf8(raw: &[u8]) -> Result<String, XMLError> {
    String::from_utf8(raw.to_vec()).map_err(XMLError::FromUtf8Error)
}

fn collect_attributes(attributes: Attributes) -> HashMap<String, String> {
    HashMap::from_iter(attributes.map(|a| {
        let a = a.unwrap();
        (from_utf8(a.key).unwrap(), from_utf8(&a.value).unwrap())
    }))
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
                    println!("Start tag: {}", from_utf8(e.name())?);

                    let node = Rc::new(RefCell::new(XMLNode {
                        name: from_utf8(e.name())?,
                        attributes: collect_attributes(e.attributes()),
                        parent: None,
                        children: Vec::new(),
                    }));

                    let current = parents.last();
                    if let Some(c) = current {
                        c.borrow_mut().children.push(node.clone());
                        node.borrow_mut().parent = Some(Rc::downgrade(c));
                    };

                    parents.push(node.clone());

                    if root.is_none() {
                        root = Some(node);
                    }
                }
                Ok(Event::Empty(ref e)) => {
                    println!("Empty tag: {}", from_utf8(e.name())?);

                    let node = Rc::new(RefCell::new(XMLNode {
                        name: from_utf8(e.name())?,
                        attributes: collect_attributes(e.attributes()),
                        parent: None,
                        children: Vec::new(),
                    }));

                    let current = parents.last();
                    if let Some(c) = current {
                        c.borrow_mut().children.push(node.clone());
                        node.borrow_mut().parent = Some(Rc::downgrade(c));
                    };

                    if root.is_none() {
                        root = Some(node);
                    }
                }
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

        let root = xml.borrow();
        assert_eq!(root.name, "tag1");
        assert_eq!(root.children.len(), 2);
        assert!(root.parent.is_none());

        let root_attributes = root.attributes.clone();
        assert_eq!(root_attributes.len(), 1);
        assert_eq!(root_attributes.get("att1").unwrap(), "test");

        let tag2 = xml.borrow().find("tag2").unwrap();
        assert_eq!(tag2.borrow().name, "tag2");
    }
}
