//! The records the typed calls return, built from the API's JSON.
//!
//! Fields a module adds are `None` when the audience hasn't installed that module (or the query left them out).
//! Decoding is lenient, like the other SDKs: a record needs its `id`, and anything else missing or of the wrong type
//! is left out rather than failing the call. Every model serializes (snake_case) so an agent can hand it on as JSON.

use chrono::{DateTime, Utc};
use serde::Serialize;
use serde_json::{Map, Value, json};

type Object = Map<String, Value>;

/// An ISO 8601 timestamp as the API sends it (`2026-11-06T20:00:00Z`), or `None`.
pub fn parse_datetime(value: Option<&Value>) -> Option<DateTime<Utc>> {
    let text = value?.as_str()?;
    DateTime::parse_from_rfc3339(text)
        .map(|at| at.with_timezone(&Utc))
        .ok()
        .or_else(|| text.parse::<chrono::NaiveDateTime>().ok().map(|naive| naive.and_utc()))
}

fn str_at(object: &Object, key: &str) -> Option<String> {
    object.get(key)?.as_str().map(String::from)
}

fn id_of(object: &Object) -> Option<String> {
    match object.get("id")? {
        Value::String(id) => Some(id.clone()),
        Value::Number(id) => Some(id.to_string()),
        _ => None,
    }
}

fn bool_at(object: &Object, key: &str) -> bool {
    object.get(key).and_then(Value::as_bool).unwrap_or(false)
}

fn int_at(object: &Object, key: &str) -> Option<i64> {
    object.get(key)?.as_i64()
}

/// The object at a path of keys, or `None` when any step is missing.
fn dig<'a>(value: Option<&'a Value>, path: &[&str]) -> Option<&'a Value> {
    path.iter().try_fold(value?, |current, key| current.get(key))
}

fn objects(value: Option<&Value>) -> Option<impl Iterator<Item = &Object>> {
    Some(value?.as_array()?.iter().filter_map(Value::as_object))
}

fn list_of<T>(value: Option<&Value>, decode: impl Fn(&Object) -> Option<T>) -> Option<Vec<T>> {
    Some(objects(value)?.filter_map(decode).collect())
}

/// Decodes each object in `nodes`, skipping any that aren't records.
pub(crate) fn decode_list<T>(value: Option<&Value>, decode: impl Fn(&Value) -> Option<T>) -> Vec<T> {
    value.and_then(Value::as_array).map(|items| items.iter().filter_map(decode).collect()).unwrap_or_default()
}

/// A latitude and longitude in degrees.
#[derive(Clone, Copy, Debug, PartialEq, Serialize)]
pub struct Coordinate {
    /// Degrees north.
    pub latitude: f64,
    /// Degrees east.
    pub longitude: f64,
}

impl Coordinate {
    /// A point; `None` when it isn't on Earth.
    pub fn new(latitude: f64, longitude: f64) -> Option<Self> {
        ((-90.0..=90.0).contains(&latitude) && (-180.0..=180.0).contains(&longitude))
            .then_some(Coordinate { latitude, longitude })
    }

    /// Parses a WKT point, `POINT (<longitude> <latitude>)`, optionally with an SRID prefix. A point that isn't on
    /// Earth (NaN, infinity, out of range, often the two swapped) is `None`.
    pub fn from_wkt(wkt: &str) -> Option<Self> {
        let open = wkt.find('(')?;
        let close = wkt.rfind(')')?;
        if close < open || !wkt[..open].to_ascii_uppercase().contains("POINT") {
            return None;
        }
        let numbers: Vec<f64> = wkt[open + 1..close].split_whitespace().filter_map(|part| part.parse().ok()).collect();
        match numbers.as_slice() {
            [longitude, latitude, ..] => Coordinate::new(*latitude, *longitude),
            _ => None,
        }
    }

    /// The point as WKT, the way the API serializes a `Geography`.
    pub fn wkt(&self) -> String {
        format!("POINT ({} {})", self.longitude, self.latitude)
    }

    /// The value to pass as a `CoordinatesInput` variable.
    pub fn coordinates_input(&self, beacon_major: Option<i64>) -> Value {
        let mut value = json!({"latitude": self.latitude, "longitude": self.longitude});
        if let Some(major) = beacon_major.filter(|major| *major != 0) {
            value["beaconMajor"] = json!(major);
        }
        value
    }
}

/// A tag on a venue, person or event: its name and chip color.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Tag {
    /// Its ID.
    pub id: String,
    /// Its name.
    pub name: String,
    /// Its chip color.
    pub color: Option<String>,
}

impl Tag {
    fn from_object(object: &Object) -> Option<Self> {
        Some(Tag {
            id: id_of(object)?,
            name: str_at(object, "name").unwrap_or_default(),
            color: str_at(object, "color"),
        })
    }
}

fn tags(value: Option<&Value>) -> Option<Vec<Tag>> {
    list_of(value, Tag::from_object)
}

/// A Facebook Page a venue or person is listed from.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Page {
    /// Its ID.
    pub id: String,
    /// Its name.
    pub name: String,
    /// Its profile photo.
    pub photo_url: Option<String>,
    /// Its cover photo.
    pub banner_url: Option<String>,
}

/// The Facebook Page in a `profile { facebook { page } }` mixin.
fn page(object: &Object) -> Option<Page> {
    let page = dig(object.get("profile"), &["facebook", "page"])?.as_object()?;
    Some(Page {
        id: id_of(page)?,
        name: str_at(page, "name").unwrap_or_default(),
        photo_url: str_at(page, "photoUrl"),
        banner_url: str_at(page, "bannerUrl"),
    })
}

/// The Google place ID in a `places { placeId }` mixin.
fn place_id(holder: Option<&Value>) -> Option<String> {
    dig(holder, &["places", "placeId"])?.as_str().map(String::from)
}

/// A locale: a city or region the audience lists venues in.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Locale {
    /// Its ID.
    pub id: String,
    /// Its name.
    pub name: Option<String>,
    /// How it is labelled in lists.
    pub label: Option<String>,
    /// The cities it covers.
    pub city_names: Option<Vec<String>>,
    /// Its banner image.
    pub banner_url: Option<String>,
    /// Its Google place ID (Google Places module).
    pub google_place_id: Option<String>,
}

impl Locale {
    /// Decodes a locale from the API's JSON.
    pub fn from_json(value: &Value) -> Option<Self> {
        Locale::from_object(value.as_object()?)
    }

    fn from_object(object: &Object) -> Option<Self> {
        Some(Locale {
            id: id_of(object)?,
            name: str_at(object, "name"),
            label: str_at(object, "label"),
            city_names: object
                .get("cityNames")
                .and_then(Value::as_array)
                .map(|names| names.iter().filter_map(|name| name.as_str().map(String::from)).collect()),
            banner_url: str_at(object, "bannerUrl"),
            google_place_id: place_id(object.get("profile")),
        })
    }
}

fn locale(value: Option<&Value>) -> Option<Locale> {
    Locale::from_object(value?.as_object()?)
}

/// Where a venue is: its point (decoded from the API's WKT), address and Google place ID.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Location {
    /// Its ID.
    pub id: String,
    /// Its point.
    pub coordinate: Option<Coordinate>,
    /// Its street address.
    pub address: Option<String>,
    /// Its Google place ID (Google Places module).
    pub google_place_id: Option<String>,
}

fn location(value: Option<&Value>) -> Option<Location> {
    let object = value?.as_object()?;
    Some(Location {
        id: id_of(object)?,
        coordinate: object.get("point").and_then(Value::as_str).and_then(Coordinate::from_wkt),
        address: str_at(object, "address"),
        google_place_id: place_id(value),
    })
}

/// A venue in the audience.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Venue {
    /// Its ID.
    pub id: String,
    /// Its name (its Facebook Page's when it has none of its own).
    pub name: String,
    /// Whether it is left out of lists.
    pub hidden: bool,
    /// Its place in lists.
    pub order: i64,
    /// Its photo.
    pub photo_url: Option<String>,
    /// Its banner image.
    pub banner_url: Option<String>,
    /// The Facebook Page it is listed from (Facebook module).
    pub page: Option<Page>,
    /// Its locale.
    pub locale: Option<Locale>,
    /// Where it is.
    pub location: Option<Location>,
    /// Its tags.
    pub tags: Option<Vec<Tag>>,
}

impl Venue {
    /// Decodes a venue from the API's JSON.
    pub fn from_json(value: &Value) -> Option<Self> {
        let object = value.as_object()?;
        let page = page(object);
        Some(Venue {
            id: id_of(object)?,
            name: str_at(object, "name").or_else(|| page.as_ref().map(|p| p.name.clone())).unwrap_or_default(),
            hidden: bool_at(object, "hidden"),
            order: int_at(object, "order").unwrap_or(0),
            photo_url: str_at(object, "photoUrl"),
            banner_url: str_at(object, "bannerUrl"),
            page,
            locale: locale(object.get("locale")),
            location: location(object.get("location")),
            tags: tags(object.get("tags")),
        })
    }
}

/// One of the signed-in person's friends, and whether they can be reached now (Friends module).
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Friend {
    /// Their ID.
    pub id: String,
    /// Their name.
    pub name: Option<String>,
    /// Their Facebook ID.
    pub facebook_id: Option<String>,
    /// Whether they're around.
    pub presence: Option<String>,
}

/// A person's home venue or gig venue.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct PersonVenue {
    /// Its ID.
    pub id: String,
    /// Its name.
    pub name: Option<String>,
    /// Its photo.
    pub photo_url: Option<String>,
    /// Its locale.
    pub locale: Option<Locale>,
    /// The signed-in person's friends there now (Friends module).
    pub friends: Option<Vec<Friend>>,
}

impl PersonVenue {
    fn from_object(object: &Object) -> Option<Self> {
        Some(PersonVenue {
            id: id_of(object)?,
            name: str_at(object, "name"),
            photo_url: str_at(object, "photoUrl"),
            locale: locale(object.get("locale")),
            friends: list_of(dig(object.get("friends"), &["list", "nodes"]), |friend| {
                Some(Friend {
                    id: id_of(friend)?,
                    name: str_at(friend, "name"),
                    facebook_id: str_at(friend, "facebookId"),
                    presence: str_at(friend, "presence"),
                })
            }),
        })
    }
}

/// The events module's `venue { name venue { … } }`: a display name and the venue, if any.
fn venue_mixin(value: Option<&Value>) -> (Option<String>, Option<&Object>) {
    let Some(mixin) = value.and_then(Value::as_object) else {
        return (None, None);
    };
    let venue = mixin.get("venue").and_then(Value::as_object).filter(|venue| venue.contains_key("id"));
    (str_at(mixin, "name"), venue)
}

/// One of a person's events.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct PersonEvent {
    /// Its ID.
    pub id: String,
    /// Its name.
    pub name: Option<String>,
    /// When it starts.
    pub start_at: Option<DateTime<Utc>>,
    /// Its locale.
    pub locale: Option<Locale>,
    /// Where it is (Venues module).
    pub venue: Option<PersonVenue>,
    /// The name it gives its venue.
    pub venue_name: Option<String>,
    /// Its tags.
    pub tags: Option<Vec<Tag>>,
}

impl PersonEvent {
    fn from_object(object: &Object) -> Option<Self> {
        let (venue_name, venue) = venue_mixin(object.get("venue"));
        Some(PersonEvent {
            id: id_of(object)?,
            name: str_at(object, "name"),
            start_at: parse_datetime(object.get("startAt")),
            locale: locale(object.get("locale")),
            venue: venue.and_then(PersonVenue::from_object),
            venue_name,
            tags: tags(object.get("tags")),
        })
    }
}

/// A group a person performs with.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Troupe {
    /// Its ID.
    pub id: String,
    /// Its name.
    pub name: Option<String>,
}

/// How a person is involved in an event: as a host or performer, and through which troupe.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct PersonEventInvolvement {
    /// The event.
    pub event: PersonEvent,
    /// `HOST`, `LINEUP`…
    pub relationship: String,
    /// Their role on the night.
    pub role: Option<String>,
    /// The troupe they're there with.
    pub via: Option<Troupe>,
}

/// A person in the audience: a DJ, performer, host or promoter.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Person {
    /// Their ID.
    pub id: String,
    /// Their name (their Facebook Page's when they have none of their own).
    pub name: String,
    /// Their avatar.
    pub avatar_url: Option<String>,
    /// Their banner image.
    pub banner_url: Option<String>,
    /// Their place in lists.
    pub order: i64,
    /// Whether they're listed in every locale.
    pub global: bool,
    /// Whether following them needs a like.
    pub like_required: bool,
    /// The Facebook Page they're listed from (Facebook module).
    pub page: Option<Page>,
    /// Their home venue (Venues module).
    pub home_venue: Option<PersonVenue>,
    /// The locales they're listed in.
    pub locales: Option<Vec<Locale>>,
    /// Their events (People module's events).
    pub event_involvements: Option<Vec<PersonEventInvolvement>>,
    /// Their tags.
    pub tags: Option<Vec<Tag>>,
}

impl Person {
    /// Decodes a person from the API's JSON.
    pub fn from_json(value: &Value) -> Option<Self> {
        let object = value.as_object()?;
        let page = page(object);
        Some(Person {
            id: id_of(object)?,
            name: str_at(object, "name").or_else(|| page.as_ref().map(|p| p.name.clone())).unwrap_or_default(),
            avatar_url: str_at(object, "avatarUrl"),
            banner_url: str_at(object, "bannerUrl"),
            order: int_at(object, "order").unwrap_or(0),
            global: bool_at(object, "global"),
            like_required: bool_at(object, "likeRequired"),
            page,
            home_venue: dig(object.get("venues"), &["home"])
                .and_then(Value::as_object)
                .and_then(PersonVenue::from_object),
            locales: list_of(object.get("locales"), Locale::from_object),
            event_involvements: list_of(dig(object.get("events"), &["involvements", "edges"]), |edge| {
                let via = edge.get("via").and_then(Value::as_object);
                Some(PersonEventInvolvement {
                    event: PersonEvent::from_object(edge.get("node")?.as_object()?)?,
                    relationship: str_at(edge, "relationship").unwrap_or_default(),
                    role: str_at(edge, "role"),
                    via: via.and_then(|via| Some(Troupe { id: id_of(via)?, name: str_at(via, "name") })),
                })
            }),
            tags: tags(object.get("tags")),
        })
    }

    /// The person's events; `None` without the People module's events.
    pub fn events(&self) -> Option<Vec<&PersonEvent>> {
        Some(self.event_involvements.as_ref()?.iter().map(|involvement| &involvement.event).collect())
    }
}

/// A venue an event or series is at.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct EventVenue {
    /// Its ID.
    pub id: String,
    /// Its name.
    pub name: Option<String>,
    /// Its photo.
    pub photo_url: Option<String>,
    /// Where it is.
    pub location: Option<Location>,
}

impl EventVenue {
    fn from_object(object: &Object) -> Option<Self> {
        Some(EventVenue {
            id: id_of(object)?,
            name: str_at(object, "name"),
            photo_url: str_at(object, "photoUrl"),
            location: location(object.get("location")),
        })
    }
}

/// Someone on an event's bill: a host or a performer on its lineup.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct EventPerson {
    /// Their ID.
    pub id: String,
    /// Their name.
    pub name: Option<String>,
    /// Their avatar.
    pub avatar_url: Option<String>,
}

fn event_people(value: Option<&Value>) -> Option<Vec<EventPerson>> {
    list_of(dig(value, &["nodes"]), |person| {
        Some(EventPerson { id: id_of(person)?, name: str_at(person, "name"), avatar_url: str_at(person, "avatarUrl") })
    })
}

/// An amount of money.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Money {
    /// In the currency's smallest unit.
    pub cents: i64,
    /// ISO 4217, e.g. `USD`.
    pub currency: String,
}

impl Money {
    fn from_value(value: Option<&Value>) -> Option<Self> {
        let object = value?.as_object()?;
        Some(Money {
            cents: int_at(object, "cents").unwrap_or(0),
            currency: str_at(object, "currency").unwrap_or_else(|| "USD".to_string()),
        })
    }
}

/// A way into an event on sale elsewhere: its price, link and seller.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct AdmissionOffer {
    /// What it costs.
    pub price: Option<Money>,
    /// Where to buy it.
    pub url: Option<String>,
    /// The seller's key.
    pub seller_key: Option<String>,
    /// The seller's name.
    pub seller_name: Option<String>,
}

/// The cover at a venue on a night.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct CoverCharge {
    /// The cover itself.
    pub amount: Option<Money>,
    /// The fee on top.
    pub fee: Option<Money>,
    /// What's paid.
    pub total: Option<Money>,
    /// The night it's for.
    pub night: String,
    /// Whether it can be paid in the app.
    pub payable: bool,
    /// When it starts being charged.
    pub from: Option<String>,
    /// The event it's for.
    pub event_id: Option<String>,
    /// That event's name.
    pub event_name: Option<String>,
}

/// The signed-in person's RSVP and how many are going (RSVP module).
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Rsvp {
    /// `ATTENDING`, `MAYBE`, `DECLINED` or `UNSURE`.
    pub mine: String,
    /// How many are going.
    pub count: i64,
}

/// An event in the audience: a night, a meetup or a conference.
///
/// `venue`/`venue_name` need the Venues module, `rsvp` RSVP, `hosts`/`lineup` People, and
/// `ticket_url`/`ticket_offers`/`cover_charge` Ticketing; each is `None` without it.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Event {
    /// Its ID.
    pub id: String,
    /// Its name.
    pub name: Option<String>,
    /// Its description.
    pub description: Option<String>,
    /// When it starts.
    pub start_at: Option<DateTime<Utc>>,
    /// When it ends.
    pub end_at: Option<DateTime<Utc>>,
    /// Whether it's featured.
    pub is_featured: bool,
    /// Whether it's canceled.
    pub is_canceled: bool,
    /// Its banner image.
    pub banner_url: Option<String>,
    /// Where it was imported from.
    pub source_url: Option<String>,
    /// Its locale.
    pub locale: Option<Locale>,
    /// Its tags.
    pub tags: Option<Vec<Tag>>,
    /// Where it is.
    pub venue: Option<EventVenue>,
    /// The name it gives its venue.
    pub venue_name: Option<String>,
    /// The RSVP.
    pub rsvp: Option<Rsvp>,
    /// Its hosts.
    pub hosts: Option<Vec<EventPerson>>,
    /// Its lineup.
    pub lineup: Option<Vec<EventPerson>>,
    /// Where tickets are sold.
    pub ticket_url: Option<String>,
    /// Tickets on sale elsewhere.
    pub ticket_offers: Option<Vec<AdmissionOffer>>,
    /// The cover.
    pub cover_charge: Option<CoverCharge>,
}

impl Event {
    /// Decodes an event from the API's JSON.
    pub fn from_json(value: &Value) -> Option<Self> {
        let object = value.as_object()?;
        let (venue_name, venue) = venue_mixin(object.get("venue"));
        let rsvp = object.get("rsvp").and_then(Value::as_object);
        let people = object.get("people");
        let tickets = object.get("tickets").and_then(Value::as_object);
        Some(Event {
            id: id_of(object)?,
            name: str_at(object, "name"),
            description: str_at(object, "description"),
            start_at: parse_datetime(object.get("startAt")),
            end_at: parse_datetime(object.get("endAt")),
            is_featured: bool_at(object, "isFeatured"),
            is_canceled: bool_at(object, "isCanceled"),
            banner_url: str_at(object, "bannerUrl"),
            source_url: str_at(object, "sourceUrl"),
            locale: locale(object.get("locale")),
            tags: tags(object.get("tags")),
            venue: venue.and_then(EventVenue::from_object),
            venue_name,
            rsvp: rsvp.map(|rsvp| Rsvp {
                mine: str_at(rsvp, "mine").unwrap_or_else(|| "UNSURE".to_string()),
                count: int_at(rsvp, "count").unwrap_or(0),
            }),
            hosts: people.and_then(|people| event_people(people.get("hosts"))),
            lineup: people.and_then(|people| event_people(people.get("lineup"))),
            ticket_url: tickets.and_then(|tickets| str_at(tickets, "url")),
            ticket_offers: tickets.and_then(|tickets| {
                list_of(dig(tickets.get("offers"), &["nodes"]), |offer| {
                    let seller = offer.get("seller");
                    Some(AdmissionOffer {
                        price: Money::from_value(offer.get("price")),
                        url: str_at(offer, "url"),
                        seller_key: dig(seller, &["key"]).and_then(Value::as_str).map(String::from),
                        seller_name: dig(seller, &["name"]).and_then(Value::as_str).map(String::from),
                    })
                })
            }),
            cover_charge: tickets
                .and_then(|tickets| dig(tickets.get("cover"), &["charge"]))
                .and_then(Value::as_object)
                .map(|charge| CoverCharge {
                    amount: Money::from_value(charge.get("amount")),
                    fee: Money::from_value(charge.get("fee")),
                    total: Money::from_value(charge.get("total")),
                    night: str_at(charge, "night").unwrap_or_default(),
                    payable: bool_at(charge, "payable"),
                    from: str_at(charge, "from"),
                    event_id: dig(charge.get("event"), &["id"]).and_then(Value::as_str).map(String::from),
                    event_name: dig(charge.get("event"), &["name"]).and_then(Value::as_str).map(String::from),
                }),
        })
    }
}

/// A recurring event by name: a weekly party, a monthly show.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct EventSeries {
    /// Its ID.
    pub id: String,
    /// Its name.
    pub name: Option<String>,
    /// Its description.
    pub description: Option<String>,
    /// How it recurs, in words ("Every Tuesday").
    pub recurrence_text: Option<String>,
    /// The first date (`YYYY-MM-DD`).
    pub starts_on: Option<String>,
    /// The start time (`HH:MM`).
    pub start_time: Option<String>,
    /// The IANA time zone its times are in.
    pub time_zone: Option<String>,
    /// How long each one runs.
    pub duration_minutes: Option<i64>,
    /// Its banner image.
    pub banner_url: Option<String>,
    /// Its locale.
    pub locale: Option<Locale>,
    /// Its tags.
    pub tags: Option<Vec<Tag>>,
    /// Where it is.
    pub venue: Option<EventVenue>,
    /// The name it gives its venue.
    pub venue_name: Option<String>,
}

impl EventSeries {
    /// Decodes a series from the API's JSON.
    pub fn from_json(value: &Value) -> Option<Self> {
        let object = value.as_object()?;
        let (venue_name, venue) = venue_mixin(object.get("venue"));
        Some(EventSeries {
            id: id_of(object)?,
            name: str_at(object, "name"),
            description: str_at(object, "description"),
            recurrence_text: str_at(object, "recurrenceText"),
            starts_on: str_at(object, "startsOn"),
            start_time: str_at(object, "startTime"),
            time_zone: str_at(object, "timeZone"),
            duration_minutes: int_at(object, "durationMinutes"),
            banner_url: str_at(object, "bannerUrl"),
            locale: locale(object.get("locale")),
            tags: tags(object.get("tags")),
            venue: venue.and_then(EventVenue::from_object),
            venue_name,
        })
    }
}

/// One of the audience's design tokens.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct ThemeToken {
    /// The token's name.
    pub name: String,
    /// Its value.
    pub value: String,
}

/// The audience's design tokens for its light and dark looks.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct AudienceTheme {
    /// The preset it starts from.
    pub preset: String,
    /// The audience's tagline.
    pub tagline: Option<String>,
    /// Light-mode tokens.
    pub light: Vec<ThemeToken>,
    /// Dark-mode tokens.
    pub dark: Vec<ThemeToken>,
}

/// The audience the client speaks for.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Audience {
    /// Its ID.
    pub id: String,
    /// Its name.
    pub name: String,
    /// Its subdomain.
    pub subdomain: String,
    /// Its theme.
    pub theme: Option<AudienceTheme>,
}

impl Audience {
    /// Decodes the audience from the API's JSON.
    pub fn from_json(value: &Value) -> Option<Self> {
        let object = value.as_object()?;
        let theme_tokens = |value: Option<&Value>| {
            list_of(value, |token| {
                Some(ThemeToken {
                    name: str_at(token, "name").unwrap_or_default(),
                    value: str_at(token, "value").unwrap_or_default(),
                })
            })
            .unwrap_or_default()
        };
        Some(Audience {
            id: id_of(object)?,
            name: str_at(object, "name").unwrap_or_default(),
            subdomain: str_at(object, "subdomain").unwrap_or_default(),
            theme: object.get("theme").and_then(Value::as_object).map(|theme| AudienceTheme {
                preset: str_at(theme, "preset").unwrap_or_default(),
                tagline: str_at(theme, "tagline"),
                light: theme_tokens(theme.get("light")),
                dark: theme_tokens(theme.get("dark")),
            }),
        })
    }
}

/// The signed-in person's own profile.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct SelfUser {
    /// Their ID.
    pub id: String,
    /// Their name.
    pub name: Option<String>,
    /// Their first name.
    pub first_name: Option<String>,
    /// Their last name.
    pub last_name: Option<String>,
    /// Their email address.
    pub email_address: Option<String>,
    /// Whether they're a platform admin.
    pub is_admin: Option<bool>,
    /// Whether they're around.
    pub presence: Option<String>,
}

impl SelfUser {
    /// Decodes a profile from the API's JSON.
    pub fn from_json(value: &Value) -> Option<Self> {
        let object = value.as_object()?;
        Some(SelfUser {
            id: id_of(object)?,
            name: str_at(object, "name"),
            first_name: str_at(object, "firstName"),
            last_name: str_at(object, "lastName"),
            email_address: str_at(object, "emailAddress"),
            is_admin: object.get("isAdmin").and_then(Value::as_bool),
            presence: str_at(object, "presence"),
        })
    }
}

/// Any record by ID: what type it is.
#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Node {
    /// Its ID.
    pub id: String,
    /// Its GraphQL type.
    pub typename: Option<String>,
}

/// An audience's public branding for a host, from `GET /v1/branding`.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct Branding {
    /// The audience that owns the host.
    pub audience_id: String,
    /// The audience's name.
    pub name: Option<String>,
    /// Everything the API sent.
    pub raw: Value,
}

impl Branding {
    /// Decodes branding from the API's JSON.
    pub fn from_json(value: &Value) -> Option<Self> {
        let object = value.as_object()?;
        let audience = object.get("audience");
        let audience_id = dig(audience, &["id"])
            .and_then(Value::as_str)
            .or_else(|| object.get("audienceId").and_then(Value::as_str))?
            .to_string();
        Some(Branding {
            audience_id,
            name: dig(audience, &["name"]).and_then(Value::as_str).map(String::from).or_else(|| str_at(object, "name")),
            raw: value.clone(),
        })
    }
}

/// One entry of the audience's public listings (`GET /v1/public/listings`): the anonymous projection its websites
/// show, readable with a `public:read` service token.
///
/// A venue or event the audience keeps to its community comes back with `visibility: "community"` and only a
/// placeholder title and description. `raw` has every field the API sent.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct PublicListing {
    /// `venue`, `event` or `post`.
    pub kind: String,
    /// Its ID.
    pub id: String,
    /// Its path on the audience's website, e.g. `/venues/<id>`.
    pub path: Option<String>,
    /// `public` or `community`.
    pub visibility: Option<String>,
    /// Its title.
    pub title: Option<String>,
    /// Its description, as plain text.
    pub description: Option<String>,
    /// A venue's (or an event's venue's) street address.
    pub address: Option<String>,
    /// A venue's phone number.
    pub phone: Option<String>,
    /// A venue's website.
    pub website: Option<String>,
    /// Whether a venue is listed among venues to go out to.
    pub listed: Option<bool>,
    /// Its image.
    pub image: Option<String>,
    /// When an event starts.
    pub start_at: Option<DateTime<Utc>>,
    /// When an event ends.
    pub end_at: Option<DateTime<Utc>>,
    /// An event's venue's name.
    pub venue_name: Option<String>,
    /// Where an event's tickets are sold.
    pub ticket_url: Option<String>,
    /// Whether an event is canceled.
    pub is_canceled: Option<bool>,
    /// An event's cover, in cents.
    pub cover_cents: Option<i64>,
    /// Everything the API sent.
    pub raw: Value,
}

impl PublicListing {
    /// Decodes a listing from the API's JSON.
    pub fn from_json(value: &Value) -> Option<Self> {
        let object = value.as_object()?;
        Some(PublicListing {
            kind: str_at(object, "kind")?,
            id: id_of(object)?,
            path: str_at(object, "path"),
            visibility: str_at(object, "visibility"),
            title: str_at(object, "title"),
            description: str_at(object, "description"),
            address: str_at(object, "address"),
            phone: str_at(object, "phone"),
            website: str_at(object, "website"),
            listed: object.get("listed").and_then(Value::as_bool),
            image: str_at(object, "image"),
            start_at: parse_datetime(object.get("start_at")),
            end_at: parse_datetime(object.get("end_at")),
            venue_name: str_at(object, "venue_name"),
            ticket_url: str_at(object, "ticket_url"),
            is_canceled: object.get("is_canceled").and_then(Value::as_bool),
            cover_cents: int_at(object, "cover_cents"),
            raw: value.clone(),
        })
    }

    /// Whether the audience shows it in full to anyone (not only to its community).
    pub fn is_public(&self) -> bool {
        self.visibility.as_deref() == Some("public")
    }
}

/// One page of the public listings.
#[derive(Clone, Debug, PartialEq, Serialize)]
pub struct PublicListingsPage {
    /// Up to 500 listings: venues, then events, then posts.
    pub listings: Vec<PublicListing>,
    /// How many pages there are.
    pub page_count: i64,
    /// The next page's number, if there is one.
    pub next_page: Option<i64>,
}

impl PublicListingsPage {
    /// Decodes a page from the API's JSON.
    pub fn from_json(value: &Value) -> Option<Self> {
        let object = value.as_object()?;
        Some(PublicListingsPage {
            listings: decode_list(object.get("listings"), PublicListing::from_json),
            page_count: int_at(object, "page_count").unwrap_or(1),
            next_page: int_at(object, "next_page"),
        })
    }
}
