//! Which fields an audience's schema has, as far as the SDK's documents need to know.

use std::collections::{HashMap, HashSet};

/// Every type's fields, by type; `None` assumes every field is there (before the SDK has had to ask).
///
/// The API leaves a module's fields out of an audience that hasn't installed it (Facebook Pages, Google Places, RSVP,
/// Ticketing, Friends…), and asking for one fails the whole operation with `undefinedField`; the SDK builds its
/// documents from this.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct SchemaShape {
    fields: Option<HashMap<String, HashSet<String>>>,
}

impl SchemaShape {
    /// Assumes every field is there: the first try of each operation, so an audience with every module needs one
    /// call.
    pub fn everything() -> Self {
        SchemaShape { fields: None }
    }

    /// The fields each type has.
    pub fn new(fields: HashMap<String, HashSet<String>>) -> Self {
        SchemaShape { fields: Some(fields) }
    }

    /// A shape with none of the module fields: what an audience with no optional modules has.
    pub fn bare() -> Self {
        SchemaShape::new(HashMap::new())
    }

    /// Whether `type_name` has `field`.
    pub fn has(&self, type_name: &str, field: &str) -> bool {
        match &self.fields {
            None => true,
            Some(fields) => fields.get(type_name).is_some_and(|names| names.contains(field)),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn shapes() {
        assert!(SchemaShape::everything().has("Venue", "profile"));
        assert!(!SchemaShape::bare().has("Venue", "profile"));
        let shape = SchemaShape::new(HashMap::from([("Venue".to_string(), HashSet::from(["name".to_string()]))]));
        assert!(shape.has("Venue", "name"));
        assert!(!shape.has("Venue", "profile"));
        assert!(!shape.has("Event", "name"));
    }
}
