//! The typed calls as data: a document, its variables, and how to read the answer. [`Client::run`] runs them.
//!
//! [`Client::run`]: crate::Client::run

use std::fmt;

use serde::Serialize;
use serde_json::{Map, Value, json};

use crate::error::{Error, Result};
use crate::models::{Audience, Coordinate, Event, EventSeries, Locale, Node, Person, SelfUser, Venue, decode_list};
use crate::queries;
use crate::schema::SchemaShape;

/// A GraphQL document: fixed text, or built from the audience's [`SchemaShape`] when it has module fields.
#[derive(Clone)]
pub enum Document {
    /// The same text for every audience.
    Fixed(String),
    /// Text that leaves out the fields an audience's schema doesn't have.
    Shaped(fn(&SchemaShape) -> String),
}

type Decode<T> = Box<dyn Fn(&Value) -> Result<T> + Send + Sync>;

/// A GraphQL operation and how to turn its `data` into a value.
pub struct Operation<T> {
    /// The operation's name, sent as `operationName`.
    pub name: String,
    /// Its document.
    pub document: Document,
    /// Its variables.
    pub variables: Option<Value>,
    /// The types to ask the schema about when the API refuses a field (`undefinedField`); empty for a fixed document.
    pub types: &'static [&'static str],
    decode: Decode<T>,
}

impl<T> fmt::Debug for Operation<T> {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Operation").field("name", &self.name).field("variables", &self.variables).finish()
    }
}

impl<T> Operation<T> {
    /// An operation with a document of your own, decoded by `decode` from the response's `data`.
    pub fn new(
        name: impl Into<String>,
        document: Document,
        decode: impl Fn(&Value) -> Result<T> + Send + Sync + 'static,
    ) -> Self {
        Operation { name: name.into(), document, variables: None, types: &[], decode: Box::new(decode) }
    }

    /// The same operation with `variables`.
    pub fn with_variables(mut self, variables: Value) -> Self {
        self.variables = Some(variables);
        self
    }

    /// The same operation, rebuilt from the schema's `types` when the API refuses a field.
    pub fn with_types(mut self, types: &'static [&'static str]) -> Self {
        self.types = types;
        self
    }

    /// The document's text for an audience's schema.
    pub fn text(&self, shape: &SchemaShape) -> String {
        match &self.document {
            Document::Fixed(text) => text.clone(),
            Document::Shaped(build) => build(shape),
        }
    }

    /// Reads the operation's value from the response's `data`.
    pub fn decode(&self, data: &Value) -> Result<T> {
        (self.decode)(data)
    }
}

/// The `nodes` (or other list) at `path` in `data`, decoded; `[]` when any step is missing.
fn list_at<T>(data: &Value, path: &[&str], decode: fn(&Value) -> Option<T>) -> Vec<T> {
    let mut value = Some(data);
    for key in path {
        value = value.and_then(|v| v.get(key));
    }
    decode_list(value, decode)
}

fn one_at<T>(data: &Value, path: &[&str], decode: fn(&Value) -> Option<T>) -> Option<T> {
    let mut value = Some(data);
    for key in path {
        value = value.and_then(|v| v.get(key));
    }
    value.filter(|v| v.is_object()).and_then(decode)
}

/// Which events: upcoming (soonest first) or past (latest first).
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, Serialize)]
#[serde(rename_all = "SCREAMING_SNAKE_CASE")]
pub enum EventWindow {
    /// Not over yet, soonest first.
    #[default]
    Upcoming,
    /// Over, most recent first.
    Past,
}

/// Which events to list.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct EventQuery {
    /// Upcoming or past.
    pub window: EventWindow,
    /// Only this locale's.
    pub locale_id: Option<String>,
    /// Only this venue's.
    pub venue_id: Option<String>,
    /// At most this many.
    pub first: u32,
}

impl Default for EventQuery {
    fn default() -> Self {
        EventQuery { window: EventWindow::Upcoming, locale_id: None, venue_id: None, first: 100 }
    }
}

fn place_variables(variables: &mut Map<String, Value>, locale_id: &Option<String>, venue_id: &Option<String>) {
    if let Some(locale) = locale_id {
        variables.insert("localeId".into(), json!(locale));
    }
    if let Some(venue) = venue_id {
        variables.insert("venueId".into(), json!(venue));
    }
}

/// The audience: name, subdomain and theme.
pub fn audience() -> Operation<Audience> {
    Operation::new("Audience", Document::Fixed(queries::AUDIENCE.into()), |data| {
        Audience::from_json(data).ok_or_else(|| Error::decoding("The audience had no id."))
    })
}

/// Every venue.
pub fn venues() -> Operation<Vec<Venue>> {
    Operation::new("Venues", Document::Shaped(queries::venues), |data| {
        Ok(list_at(data, &["venues", "list", "nodes"], Venue::from_json))
    })
    .with_types(queries::LISTING_TYPES)
}

/// Every person listed.
pub fn people() -> Operation<Vec<Person>> {
    Operation::new("People", Document::Shaped(queries::people), |data| {
        Ok(list_at(data, &["people", "list", "nodes"], Person::from_json))
    })
    .with_types(queries::LISTING_TYPES)
}

/// Every locale.
pub fn locales() -> Operation<Vec<Locale>> {
    Operation::new("Locales", Document::Shaped(queries::locales), |data| {
        Ok(list_at(data, &["locales"], Locale::from_json))
    })
    .with_types(queries::LISTING_TYPES)
}

/// The locale nearest `position`, if any is near.
pub fn closest_locale(position: Coordinate, beacon_major: Option<i64>) -> Operation<Option<Locale>> {
    Operation::new("ClosestLocale", Document::Shaped(queries::closest_locale), |data| {
        Ok(one_at(data, &["closestLocale"], Locale::from_json))
    })
    .with_variables(json!({"near": position.coordinates_input(beacon_major)}))
    .with_types(queries::LISTING_TYPES)
}

/// The signed-in person's profile; `None` for a credential with no person.
pub fn me() -> Operation<Option<SelfUser>> {
    Operation::new("Me", Document::Fixed(queries::ME.into()), |data| {
        Ok(one_at(data, &["me", "self"], SelfUser::from_json))
    })
}

/// Any record's type, by ID.
pub fn node(id: &str) -> Operation<Option<Node>> {
    Operation::new("Node", Document::Fixed(queries::NODE.into()), |data| {
        Ok(one_at(data, &["node"], |node| {
            Some(Node {
                id: node.get("id")?.as_str()?.to_string(),
                typename: node.get("__typename").and_then(Value::as_str).map(String::from),
            })
        }))
    })
    .with_variables(json!({"id": id}))
}

/// Events in a window.
pub fn events(query: &EventQuery) -> Operation<Vec<Event>> {
    let mut variables = Map::new();
    variables.insert("window".into(), json!(query.window));
    variables.insert("first".into(), json!(query.first));
    place_variables(&mut variables, &query.locale_id, &query.venue_id);
    Operation::new("Events", Document::Shaped(queries::events), |data| {
        Ok(list_at(data, &["events", "list", "nodes"], Event::from_json))
    })
    .with_variables(Value::Object(variables))
    .with_types(queries::EVENT_TYPES)
}

/// One event, if it exists.
pub fn event(id: &str) -> Operation<Option<Event>> {
    Operation::new("Event", Document::Shaped(queries::event), |data| {
        Ok(one_at(data, &["events", "event"], Event::from_json))
    })
    .with_variables(json!({"id": id}))
    .with_types(queries::EVENT_TYPES)
}

/// Recurring events, optionally in one locale or at one venue.
pub fn event_series(locale_id: Option<&str>, venue_id: Option<&str>, first: u32) -> Operation<Vec<EventSeries>> {
    let mut variables = Map::new();
    variables.insert("first".into(), json!(first));
    place_variables(&mut variables, &locale_id.map(String::from), &venue_id.map(String::from));
    Operation::new("EventSeries", Document::Shaped(queries::event_series), |data| {
        Ok(list_at(data, &["events", "series", "nodes"], EventSeries::from_json))
    })
    .with_variables(Value::Object(variables))
    .with_types(queries::EVENT_TYPES)
}

/// Every document a typed call can send, built for an audience with every module (`<OperationName>`, text), for
/// checking them against the API's schema.
pub fn documents() -> Vec<(String, String)> {
    let shape = SchemaShape::everything();
    let coordinate = Coordinate { latitude: 0.0, longitude: 0.0 };
    vec![
        (audience().name, audience().text(&shape)),
        (venues().name, venues().text(&shape)),
        (people().name, people().text(&shape)),
        (locales().name, locales().text(&shape)),
        (closest_locale(coordinate, None).name, closest_locale(coordinate, None).text(&shape)),
        (me().name, me().text(&shape)),
        (node("x").name, node("x").text(&shape)),
        (events(&EventQuery::default()).name, events(&EventQuery::default()).text(&shape)),
        (event("x").name, event("x").text(&shape)),
        (event_series(None, None, 1).name, event_series(None, None, 1).text(&shape)),
    ]
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn variables() {
        let query = EventQuery {
            window: EventWindow::Past,
            locale_id: Some("l-1".into()),
            venue_id: Some("v-1".into()),
            first: 5,
        };
        assert_eq!(
            events(&query).variables,
            Some(json!({"window": "PAST", "first": 5, "localeId": "l-1", "venueId": "v-1"}))
        );
        assert_eq!(events(&EventQuery::default()).variables, Some(json!({"window": "UPCOMING", "first": 100})));
        assert_eq!(event_series(Some("l"), None, 3).variables, Some(json!({"first": 3, "localeId": "l"})));
        let near = Coordinate::new(46.87, -113.99).unwrap();
        assert_eq!(
            closest_locale(near, Some(7)).variables,
            Some(json!({"near": {"latitude": 46.87, "longitude": -113.99, "beaconMajor": 7}}))
        );
        assert_eq!(node("n").variables, Some(json!({"id": "n"})));
    }

    #[test]
    fn decoding_tolerates_missing_parts() {
        assert!(venues().decode(&json!({})).unwrap().is_empty());
        assert!(event("x").decode(&json!({"events": {"event": null}})).unwrap().is_none());
        assert!(me().decode(&json!({"me": null})).unwrap().is_none());
        assert!(audience().decode(&json!({})).is_err());
        let found = node("n").decode(&json!({"node": {"id": "n", "__typename": "Venue"}})).unwrap().unwrap();
        assert_eq!(found.typename.as_deref(), Some("Venue"));
        assert!(format!("{:?}", venues()).contains("Venues"));
    }

    #[test]
    fn every_document_is_named_for_its_operation() {
        for (name, text) in documents() {
            assert!(text.starts_with(&format!("query {name}")), "{name}: {text}");
        }
    }
}
