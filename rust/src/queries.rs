//! The GraphQL documents behind the typed calls: the same module-shaped fragments as the other SDKs, which
//! [`models`](crate::models) read.
//!
//! Fragments with module fields take the audience's [`SchemaShape`]: the API leaves a module's fields out of an
//! audience that hasn't installed it, and asking for one fails the whole operation.

use crate::schema::SchemaShape;

const PAGE_FIELDS: &str = "id name photoUrl bannerUrl";
const TAG_FIELDS: &str = "id name color";
const MONEY_FIELDS: &str = "cents currency";

/// The types whose fields the listing documents depend on.
pub const LISTING_TYPES: &[&str] = &["Locale", "ListingProfile", "Venue", "Location", "Person", "Event"];

/// The types whose fields the event documents depend on.
pub const EVENT_TYPES: &[&str] =
    &["Locale", "ListingProfile", "Venue", "Location", "Person", "Event", "EventSeries", "EventTickets"];

fn admission_offer_fields() -> String {
    format!("price {{ {MONEY_FIELDS} }} url seller {{ key name }}")
}

fn cover_charge_fields() -> String {
    format!(
        "amount {{ {MONEY_FIELDS} }} fee {{ {MONEY_FIELDS} }} total {{ {MONEY_FIELDS} }} night from payable \
         event {{ id name }}"
    )
}

fn when(condition: bool, text: impl Into<String>) -> String {
    if condition { text.into() } else { String::new() }
}

/// A locale's fields.
pub fn locale_fields(shape: &SchemaShape) -> String {
    let places = when(
        shape.has("Locale", "profile") && shape.has("ListingProfile", "places"),
        " profile { places { placeId } }",
    );
    format!("id name label cityNames bannerUrl{places}")
}

fn page_mixin(shape: &SchemaShape, type_name: &str) -> String {
    when(
        shape.has(type_name, "profile") && shape.has("ListingProfile", "facebook"),
        format!(" profile {{ facebook {{ page {{ {PAGE_FIELDS} }} }} }}"),
    )
}

fn location_fields(shape: &SchemaShape) -> String {
    let place = when(shape.has("Location", "places"), " places { placeId }");
    format!("id point address{place}")
}

/// A venue's fields.
pub fn venue_fields(shape: &SchemaShape) -> String {
    format!(
        "id name hidden order photoUrl bannerUrl{page} locale {{ {locale} }} location {{ {location} }} \
         tags {{ {TAG_FIELDS} }}",
        page = page_mixin(shape, "Venue"),
        locale = locale_fields(shape),
        location = location_fields(shape),
    )
}

fn person_venue_fields(shape: &SchemaShape) -> String {
    let friends = when(shape.has("Venue", "friends"), " friends { list { nodes { id name facebookId presence } } }");
    format!("id name photoUrl locale {{ id name }}{friends}")
}

fn person_event_fields(shape: &SchemaShape) -> String {
    let venue =
        when(shape.has("Event", "venue"), format!(" venue {{ name venue {{ {} }} }}", person_venue_fields(shape)));
    format!("id name startAt locale {{ id name }}{venue} tags {{ {TAG_FIELDS} }}")
}

/// A person's fields.
pub fn person_fields(shape: &SchemaShape) -> String {
    let venues =
        when(shape.has("Person", "venues"), format!(" venues {{ home {{ {} }} }}", person_venue_fields(shape)));
    let events = when(
        shape.has("Person", "events"),
        format!(
            " events {{ involvements {{ edges {{ relationship role via {{ id name }} node {{ {} }} }} }} }}",
            person_event_fields(shape)
        ),
    );
    format!(
        "id name avatarUrl bannerUrl order global likeRequired{page}{venues} locales {{ id name }}{events} \
         tags {{ {TAG_FIELDS} }}",
        page = page_mixin(shape, "Person"),
    )
}

fn event_venue_fields(shape: &SchemaShape) -> String {
    format!("venue {{ name venue {{ id name photoUrl location {{ {} }} }} }}", location_fields(shape))
}

fn event_tickets_fields(shape: &SchemaShape) -> String {
    let cover =
        when(shape.has("EventTickets", "cover"), format!(" cover {{ charge {{ {} }} }}", cover_charge_fields()));
    format!("tickets {{ url offers {{ nodes {{ {} }} }}{cover} }}", admission_offer_fields())
}

/// An event's fields.
pub fn event_fields(shape: &SchemaShape) -> String {
    let mut fields = format!(
        "id name description startAt endAt isFeatured isCanceled bannerUrl sourceUrl locale {{ {} }} \
         tags {{ {TAG_FIELDS} }}",
        locale_fields(shape)
    );
    if shape.has("Event", "venue") {
        fields.push(' ');
        fields.push_str(&event_venue_fields(shape));
    }
    if shape.has("Event", "rsvp") {
        fields.push_str(" rsvp { mine count }");
    }
    if shape.has("Event", "people") {
        fields.push_str(" people { hosts { nodes { id name avatarUrl } } lineup { nodes { id name avatarUrl } } }");
    }
    if shape.has("Event", "tickets") {
        fields.push(' ');
        fields.push_str(&event_tickets_fields(shape));
    }
    fields
}

/// An event series' fields.
pub fn event_series_fields(shape: &SchemaShape) -> String {
    let venue = when(shape.has("EventSeries", "venue"), format!(" {}", event_venue_fields(shape)));
    format!(
        "id name description recurrenceText startsOn startTime timeZone durationMinutes bannerUrl \
         locale {{ {} }} tags {{ {TAG_FIELDS} }}{venue}",
        locale_fields(shape)
    )
}

/// The audience: its name, subdomain and theme.
pub const AUDIENCE: &str =
    "query Audience { id name subdomain theme { preset tagline light { name value } dark { name value } } }";

/// The signed-in person's own profile.
pub const ME: &str = "query Me { me { self { id name firstName lastName emailAddress isAdmin presence } } }";

/// Any record by ID: its type.
pub const NODE: &str = "query Node($id: ID!) { node(id: $id) { __typename id } }";

/// Every venue.
pub fn venues(shape: &SchemaShape) -> String {
    format!("query Venues {{ venues {{ list {{ nodes {{ {} }} }} }} }}", venue_fields(shape))
}

/// Every person listed (DJs, performers, hosts, promoters).
pub fn people(shape: &SchemaShape) -> String {
    format!("query People {{ people {{ list {{ nodes {{ {} }} }} }} }}", person_fields(shape))
}

/// Every locale.
pub fn locales(shape: &SchemaShape) -> String {
    format!("query Locales {{ locales {{ {} }} }}", locale_fields(shape))
}

/// The locale nearest a point.
pub fn closest_locale(shape: &SchemaShape) -> String {
    format!(
        "query ClosestLocale($near: CoordinatesInput!) {{ closestLocale(near: $near) {{ {} }} }}",
        locale_fields(shape)
    )
}

/// Events in a window, optionally in one locale or at one venue.
pub fn events(shape: &SchemaShape) -> String {
    format!(
        "query Events($window: EventWindow, $localeId: ID, $venueId: ID, $first: Int) {{ events {{ \
         list(window: $window, localeId: $localeId, venueId: $venueId, first: $first) {{ nodes {{ {} }} }} }} }}",
        event_fields(shape)
    )
}

/// One event.
pub fn event(shape: &SchemaShape) -> String {
    format!("query Event($id: ID!) {{ events {{ event(id: $id) {{ {} }} }} }}", event_fields(shape))
}

/// Recurring events, optionally in one locale or at one venue.
pub fn event_series(shape: &SchemaShape) -> String {
    format!(
        "query EventSeries($localeId: ID, $venueId: ID, $first: Int) {{ events {{ \
         series(localeId: $localeId, venueId: $venueId, first: $first) {{ nodes {{ {} }} }} }} }}",
        event_series_fields(shape)
    )
}

/// Introspection of which fields each of `types` has: `t0: __type(name: "…") { fields { name } }`.
pub fn schema_fields(types: &[&str]) -> String {
    let selections: Vec<String> = types
        .iter()
        .enumerate()
        .map(|(index, name)| {
            format!("t{index}: __type(name: \"{name}\") {{ fields(includeDeprecated: true) {{ name }} }}")
        })
        .collect();
    format!("query SchemaFields {{ {} }}", selections.join(" "))
}

// Soapbox (news)

/// The types the Soapbox documents depend on: the root's `soapbox` and each listing's `articles`.
pub const SOAPBOX_TYPES: &[&str] = &["Audience", "Venue", "Event", "Person", "Locale", "Article", "Publication"];

const PUBLICATION_SUMMARY_FIELDS: &str = "id name photoUrl trusted acceptsOpEds";
const ARTICLE_SUBJECT_FIELDS: &str = "venues { id name } events { id name } people { id name } locales { id name }";
const PUBLICATION_FIELDS: &str = "id name masthead about websiteUrl photoUrl trusted acceptsOpEds opEdGuidelines locale { id name } person { id name }";

/// An article's fields, as lists show it (no body).
pub fn article_fields(_shape: &SchemaShape) -> String {
    format!(
        "id slug title summary byline kind publishedAt edited pinned teaser canonicalUrl disclosure heroPhotoUrl \
         heroAltText publication {{ {PUBLICATION_SUMMARY_FIELDS} }}"
    )
}

/// The document for an audience without Soapbox: asks for nothing the models read, under the operation's name.
fn no_soapbox(name: &str) -> String {
    format!("query {name} {{ id }}")
}

/// The audience's live articles, pinned first, then newest.
pub fn articles(shape: &SchemaShape) -> String {
    if !shape.has("Audience", "soapbox") {
        return no_soapbox("Articles");
    }
    format!(
        "query Articles($localeId: ID, $publicationId: ID, $first: Int) {{\n  soapbox {{ articles(localeId: $localeId, \
         publicationId: $publicationId, first: $first) {{\n    nodes {{ {} }}\n  }} }}\n}}",
        article_fields(shape)
    )
}

/// A page of articles, with the cursor for the next.
pub fn articles_page(shape: &SchemaShape) -> String {
    if !shape.has("Audience", "soapbox") {
        return no_soapbox("ArticlesPage");
    }
    format!(
        "query ArticlesPage($localeId: ID, $publicationId: ID, $first: Int, $after: String) {{\n  soapbox {{ \
         articles(localeId: $localeId, publicationId: $publicationId, first: $first, after: $after) {{\n    nodes {{ \
         {} }}\n    pageInfo {{ endCursor hasNextPage }}\n  }} }}\n}}",
        article_fields(shape)
    )
}

/// Articles featured nationally.
pub fn national_articles(shape: &SchemaShape) -> String {
    if !shape.has("Audience", "soapbox") || !shape.has("Article", "featuredNationally") {
        return no_soapbox("NationalArticles");
    }
    format!(
        "query NationalArticles($localeId: ID, $first: Int) {{\n  soapbox {{ articles(national: true, localeId: \
         $localeId, first: $first) {{\n    nodes {{ {} featuredNationally }}\n  }} }}\n}}",
        article_fields(shape)
    )
}

/// One article, with its body and what it is about.
pub fn article(shape: &SchemaShape) -> String {
    if !shape.has("Audience", "soapbox") {
        return no_soapbox("Article");
    }
    format!(
        "query Article($id: ID!) {{\n  soapbox {{ article(id: $id) {{ {} body {ARTICLE_SUBJECT_FIELDS} }} }}\n}}",
        article_fields(shape)
    )
}

/// The publications the audience carries.
pub fn publications(shape: &SchemaShape) -> String {
    if !shape.has("Audience", "soapbox") {
        return no_soapbox("Publications");
    }
    format!("query Publications {{\n  soapbox {{ publications {{ {PUBLICATION_FIELDS} }} }}\n}}")
}

/// One publication.
pub fn publication(shape: &SchemaShape) -> String {
    if !shape.has("Audience", "soapbox") {
        return no_soapbox("Publication");
    }
    format!("query Publication($id: ID!) {{\n  soapbox {{ publication(id: $id) {{ {PUBLICATION_FIELDS} }} }}\n}}")
}

fn articles_about(shape: &SchemaShape, type_name: &str, open: &str, close: &str) -> String {
    if !shape.has(type_name, "articles") {
        return no_soapbox("ArticlesAbout");
    }
    format!(
        "query ArticlesAbout($id: ID!, $first: Int) {{\n  {open}articles {{ list(first: $first) {{ nodes {{ {} }} }} \
         }}{close}\n}}",
        article_fields(shape)
    )
}

/// Live articles about a venue.
pub fn articles_about_venue(shape: &SchemaShape) -> String {
    articles_about(shape, "Venue", "venues { venue(id: $id) { ", " } }")
}

/// Live articles about an event.
pub fn articles_about_event(shape: &SchemaShape) -> String {
    articles_about(shape, "Event", "events { event(id: $id) { ", " } }")
}

/// Live articles about a person.
pub fn articles_about_person(shape: &SchemaShape) -> String {
    articles_about(shape, "Person", "people { person(id: $id) { ", " } }")
}

/// Live articles about a locale.
pub fn articles_about_locale(shape: &SchemaShape) -> String {
    articles_about(shape, "Locale", "locale(id: $id) { ", " }")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn module_fields_follow_the_shape() {
        let full = SchemaShape::everything();
        let bare = SchemaShape::bare();
        assert!(venues(&full).contains("profile { facebook { page"));
        assert!(venues(&full).contains("places { placeId }"));
        assert!(!venues(&bare).contains("profile"));
        assert!(!venues(&bare).contains("places"));
        assert!(people(&full).contains("events { involvements"));
        assert!(people(&full).contains("friends { list"));
        assert!(!people(&bare).contains("involvements"));
        assert!(!people(&bare).contains("venues {"));
        for part in ["venue { name venue", "rsvp { mine count }", "people { hosts", "tickets { url", "cover { charge"] {
            assert!(events(&full).contains(part), "{part}");
            assert!(!events(&bare).contains(part), "{part}");
        }
        assert!(event_series(&full).contains("venue { name venue"));
        assert!(!event_series(&bare).contains("venue {"));
        assert!(closest_locale(&full).starts_with("query ClosestLocale($near: CoordinatesInput!)"));
        assert!(event(&bare).starts_with("query Event($id: ID!)"));
        assert!(locales(&bare).starts_with("query Locales"));
    }

    #[test]
    fn introspection() {
        assert_eq!(
            schema_fields(&["Venue", "Event"]),
            "query SchemaFields { t0: __type(name: \"Venue\") { fields(includeDeprecated: true) { name } } \
             t1: __type(name: \"Event\") { fields(includeDeprecated: true) { name } } }"
        );
    }
}
