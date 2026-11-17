//! The client against a fake API (wiremock): credentials, the schema retry, the typed calls and public listings.

use audiencekit::{
    Auth, Client, Configuration, Coordinate, Credential, Environment, EventQuery, EventWindow, ListingKind, codes,
};
use serde_json::{Value, json};
use wiremock::matchers::{body_partial_json, header, method, path, query_param};
use wiremock::{Mock, MockServer, Request, Respond, ResponseTemplate};

const AUDIENCE: &str = "6c1b0f7e-0000-4000-8000-000000000001";
const GRAPHQL: &str = "/v1/audience/6c1b0f7e-0000-4000-8000-000000000001/graphql";

fn service_session(server: &MockServer, token: &str) -> Value {
    json!({
        "token": token, "userId": null, "audienceId": AUDIENCE, "role": "service",
        "endpoint": format!("{}{GRAPHQL}", server.uri()), "venueDeviceId": null,
        "expiresAt": "2099-01-01T00:00:00Z", "audience": "Hot Mess", "scopes": ["public:read"]
    })
}

async fn trade(server: &MockServer, token: &str, times: u64) {
    Mock::given(method("POST"))
        .and(path("/v1/token/service"))
        .and(body_partial_json(json!({"service_token": "akst_ab_secret"})))
        .respond_with(ResponseTemplate::new(200).set_body_json(service_session(server, token)))
        .expect(times)
        .mount(server)
        .await;
}

fn service_client(server: &MockServer) -> Client {
    Client::builder().base_url(server.uri()).service_token("akst_ab_secret").build().unwrap()
}

/// Answers GraphQL by operation name.
struct Operations(Vec<(&'static str, Value)>);

impl Respond for Operations {
    fn respond(&self, request: &Request) -> ResponseTemplate {
        let body: Value = serde_json::from_slice(&request.body).unwrap();
        let name = body["operationName"].as_str().unwrap_or_default();
        match self.0.iter().find(|(operation, _)| *operation == name) {
            Some((_, answer)) => ResponseTemplate::new(200).set_body_json(answer),
            None => ResponseTemplate::new(200).set_body_json(json!({"errors": [{"message": format!("no {name}")}]})),
        }
    }
}

fn venue_json() -> Value {
    json!({
        "id": "v-1", "name": null, "hidden": false, "order": 2, "photoUrl": "https://cdn/p.jpg", "bannerUrl": null,
        "profile": {"facebook": {"page": {"id": "fb-1", "name": "The Edge", "photoUrl": null, "bannerUrl": null}}},
        "locale": {"id": "l-1", "name": "Missoula", "label": "MSO", "cityNames": ["Missoula"], "bannerUrl": null,
                   "profile": {"places": {"placeId": "gp-l"}}},
        "location": {"id": "loc-1", "point": "SRID=4326;POINT (-113.994 46.872)", "address": "123 Higgins Ave",
                     "places": {"placeId": "gp-v"}},
        "tags": [{"id": "t-1", "name": "Karaoke", "color": "#f0f"}, "junk"]
    })
}

fn event_json() -> Value {
    json!({
        "id": "e-1", "name": "Drag Brunch", "description": "Mimosas", "startAt": "2026-11-20T18:00:00Z",
        "endAt": "2026-11-20T21:00:00.000-07:00", "isFeatured": true, "isCanceled": false, "bannerUrl": null,
        "sourceUrl": "https://example.test/e", "locale": {"id": "l-1", "name": "Missoula"}, "tags": [],
        "venue": {"name": "The Edge", "venue": {"id": "v-1", "name": "The Edge", "photoUrl": null,
                  "location": {"id": "loc-1", "point": "POINT (-113.994 46.872)", "address": null}}},
        "rsvp": {"mine": "ATTENDING", "count": 12},
        "people": {"hosts": {"nodes": [{"id": "p-1", "name": "Kiki", "avatarUrl": null}]},
                   "lineup": {"nodes": [{"id": "p-2", "name": "DJ Lux", "avatarUrl": null}]}},
        "tickets": {"url": "https://tix.test", "offers": {"nodes": [
                       {"price": {"cents": 1500, "currency": "USD"}, "url": "https://tix.test/1",
                        "seller": {"key": "eventbrite", "name": "Eventbrite"}}]},
                    "cover": {"charge": {"amount": {"cents": 1000, "currency": "USD"},
                                          "fee": {"cents": 100, "currency": "USD"}, "total": {"cents": 1100},
                                          "night": "2026-11-20", "from": "21:00", "payable": true,
                                          "event": {"id": "e-1", "name": "Drag Brunch"}}}}
    })
}

fn person_json() -> Value {
    json!({
        "id": "p-1", "name": "Kiki Riot", "avatarUrl": "https://cdn/k.jpg", "bannerUrl": null, "order": 1,
        "global": true, "likeRequired": false,
        "venues": {"home": {"id": "v-1", "name": "The Edge", "photoUrl": null, "locale": {"id": "l-1", "name": "Missoula"},
                            "friends": {"list": {"nodes": [{"id": "u-9", "name": "Sam R.", "facebookId": null, "presence": "HERE"}]}}}},
        "locales": [{"id": "l-1", "name": "Missoula"}],
        "events": {"involvements": {"edges": [
            {"relationship": "HOST", "role": "Emcee", "via": {"id": "tr-1", "name": "House of Lux"},
             "node": {"id": "e-1", "name": "Drag Brunch", "startAt": "2026-11-20T18:00:00Z",
                      "locale": {"id": "l-1", "name": "Missoula"},
                      "venue": {"name": "The Edge", "venue": {"id": "v-1", "name": "The Edge"}}, "tags": []}},
            {"relationship": "LINEUP", "node": null}
        ]}},
        "tags": [{"id": "t-2", "name": "Drag"}]
    })
}

#[tokio::test]
async fn a_service_token_is_traded_once_and_its_audience_is_queried() {
    let server = MockServer::start().await;
    trade(&server, "jwt-1", 1).await;
    Mock::given(method("POST"))
        .and(path(GRAPHQL))
        .and(header("authorization", "Bearer jwt-1"))
        .and(header("x-audiencekit-api-version", audiencekit::config::API_VERSION))
        .and(header("x-apollo-operation-type", "query"))
        .and(header("x-apollo-operation-name", "Venues"))
        .respond_with(
            ResponseTemplate::new(200)
                .set_body_json(json!({"data": {"venues": {"list": {"nodes": [venue_json(), {"name": "no id"}]}}}})),
        )
        .expect(2)
        .mount(&server)
        .await;

    let client = service_client(&server);
    let venues = client.venues().await.unwrap();
    assert_eq!(venues.len(), 1);
    let venue = &venues[0];
    assert_eq!(venue.name, "The Edge", "falls back to the Facebook Page's name");
    assert_eq!(venue.order, 2);
    assert_eq!(venue.page.as_ref().unwrap().id, "fb-1");
    let locale = venue.locale.as_ref().unwrap();
    assert_eq!(
        (locale.google_place_id.as_deref(), locale.city_names.clone()),
        (Some("gp-l"), Some(vec!["Missoula".to_string()]))
    );
    let location = venue.location.as_ref().unwrap();
    assert_eq!(location.coordinate, Coordinate::new(46.872, -113.994));
    assert_eq!(location.google_place_id.as_deref(), Some("gp-v"));
    assert_eq!(venue.tags.as_ref().unwrap()[0].color.as_deref(), Some("#f0f"));

    client.venues().await.unwrap();
    let credential = client.credential().await.unwrap().unwrap();
    assert_eq!((credential.role.as_str(), credential.audience.as_deref()), ("service", Some("Hot Mess")));
    assert_eq!(client.audience_id().await.unwrap(), AUDIENCE);
    let json = serde_json::to_value(&venues).unwrap();
    assert_eq!(json[0]["location"]["coordinate"]["latitude"], json!(46.872));
}

#[tokio::test]
async fn a_refused_service_session_is_traded_again_once() {
    let server = MockServer::start().await;
    trade(&server, "jwt-1", 2).await;
    Mock::given(method("POST"))
        .and(path(GRAPHQL))
        .respond_with(ResponseTemplate::new(401).set_body_json(json!({"error": "unauthenticated"})))
        .expect(2)
        .mount(&server)
        .await;
    let error = service_client(&server).locales().await.unwrap_err();
    assert_eq!(error.code(), codes::UNAUTHENTICATED);
    assert_eq!(error.status(), Some(401));
}

#[tokio::test]
async fn a_revoked_service_token_says_so() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/v1/token/service"))
        .respond_with(ResponseTemplate::new(401).set_body_json(json!({"error": "unauthenticated"})))
        .mount(&server)
        .await;
    let error = service_client(&server).venues().await.unwrap_err();
    assert!(error.is_unauthenticated());
    assert!(error.message().contains("service token"));

    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/v1/token/service"))
        .respond_with(
            ResponseTemplate::new(403).set_body_json(json!({"error": "forbidden", "message": "Preview only"})),
        )
        .mount(&server)
        .await;
    assert_eq!(service_client(&server).venues().await.unwrap_err().message(), "Preview only");

    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path("/v1/token/service"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({"token": "x"})))
        .mount(&server)
        .await;
    assert_eq!(service_client(&server).venues().await.unwrap_err().code(), codes::DECODING);
}

#[tokio::test]
async fn an_audience_without_a_module_gets_a_second_try_without_its_fields() {
    let server = MockServer::start().await;
    trade(&server, "jwt-1", 1).await;
    let undefined = json!({"errors": [{"message": "Field 'tickets' doesn't exist on type 'Event'",
                                      "extensions": {"code": "undefinedField"}}]});
    // The first try asks for tickets and is refused; after introspection, the second leaves them out.
    Mock::given(method("POST"))
        .and(path(GRAPHQL))
        .and(body_partial_json(json!({"operationName": "Events"})))
        .respond_with(move |request: &Request| {
            let body: Value = serde_json::from_slice(&request.body).unwrap();
            let query = body["query"].as_str().unwrap();
            if query.contains("tickets") {
                ResponseTemplate::new(200).set_body_json(undefined.clone())
            } else {
                assert!(!query.contains("rsvp"), "the schema said Event has no rsvp");
                assert_eq!(body["variables"], json!({"window": "PAST", "first": 3, "localeId": "l-1"}));
                ResponseTemplate::new(200)
                    .set_body_json(json!({"data": {"events": {"list": {"nodes": [event_json()]}}}}))
            }
        })
        .expect(3)
        .mount(&server)
        .await;
    let event_fields: Vec<Value> = [
        "id",
        "name",
        "description",
        "startAt",
        "endAt",
        "isFeatured",
        "isCanceled",
        "bannerUrl",
        "sourceUrl",
        "locale",
        "tags",
        "venue",
        "people",
    ]
    .iter()
    .map(|name| json!({"name": name}))
    .collect();
    Mock::given(method("POST"))
        .and(path(GRAPHQL))
        .and(body_partial_json(json!({"operationName": "SchemaFields"})))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({"data": {
            "t0": {"fields": [{"name": "id"}]}, "t1": {"fields": []}, "t2": {"fields": [{"name": "id"}]},
            "t3": {"fields": [{"name": "id"}, {"name": "places"}]}, "t4": null, "t5": {"fields": event_fields},
            "t6": {"fields": []}, "t7": {"fields": []}
        }})))
        .expect(1)
        .mount(&server)
        .await;

    let client = service_client(&server);
    let query = EventQuery { window: EventWindow::Past, locale_id: Some("l-1".into()), venue_id: None, first: 3 };
    let events = client.events(&query).await.unwrap();
    let event = &events[0];
    assert_eq!(event.name.as_deref(), Some("Drag Brunch"));
    assert_eq!(event.end_at.unwrap().to_rfc3339(), "2026-11-21T04:00:00+00:00");
    assert_eq!(event.venue_name.as_deref(), Some("The Edge"));
    assert_eq!(
        event.venue.as_ref().unwrap().location.as_ref().unwrap().coordinate.unwrap().wkt(),
        "POINT (-113.994 46.872)"
    );
    assert_eq!(event.rsvp.as_ref().unwrap().count, 12);
    assert_eq!(event.hosts.as_ref().unwrap()[0].name.as_deref(), Some("Kiki"));
    assert_eq!(event.lineup.as_ref().unwrap()[0].id, "p-2");
    assert_eq!(event.ticket_url.as_deref(), Some("https://tix.test"));
    let offer = &event.ticket_offers.as_ref().unwrap()[0];
    assert_eq!((offer.price.as_ref().unwrap().cents, offer.seller_name.as_deref()), (1500, Some("Eventbrite")));
    let cover = event.cover_charge.as_ref().unwrap();
    assert_eq!(
        (cover.total.as_ref().unwrap().currency.as_str(), cover.payable, cover.event_name.as_deref()),
        ("USD", true, Some("Drag Brunch"))
    );

    // The schema is cached: the next call goes straight to the shaped document.
    client.events(&query).await.unwrap();
}

#[tokio::test]
async fn other_graphql_errors_are_not_retried() {
    let server = MockServer::start().await;
    trade(&server, "jwt-1", 1).await;
    Mock::given(method("POST"))
        .and(path(GRAPHQL))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({"data": {"people": null},
            "errors": [{"message": "A service token reaches only what its scopes are for", "extensions": {"code": "FORBIDDEN"}}]})))
        .expect(1)
        .mount(&server)
        .await;
    let error = service_client(&server).people().await.unwrap_err();
    assert_eq!(error.code(), codes::FORBIDDEN);
    assert_eq!(error.errors().len(), 1);
}

#[tokio::test]
async fn people_series_and_the_rest_of_the_typed_calls() {
    let server = MockServer::start().await;
    trade(&server, "jwt-1", 1).await;
    let series = json!({"id": "s-1", "name": "Karaoke Tuesdays", "recurrenceText": "Every Tuesday", "startsOn": "2026-01-06",
        "startTime": "21:00", "timeZone": "America/Denver", "durationMinutes": 180, "description": null, "bannerUrl": null,
        "locale": {"id": "l-1"}, "tags": [], "venue": {"name": "The Edge", "venue": {"id": "v-1", "name": "The Edge"}}});
    Mock::given(method("POST"))
        .and(path(GRAPHQL))
        .respond_with(Operations(vec![
            ("People", json!({"data": {"people": {"list": {"nodes": [person_json()]}}}})),
            ("EventSeries", json!({"data": {"events": {"series": {"nodes": [series]}}}})),
            ("Event", json!({"data": {"events": {"event": event_json()}}})),
            ("Node", json!({"data": {"node": {"__typename": "Venue", "id": "v-1"}}})),
            ("Me", json!({"data": {"me": null}})),
            ("ClosestLocale", json!({"data": {"closestLocale": {"id": "l-1", "name": "Missoula"}}})),
            ("Audience", json!({"data": {"id": AUDIENCE, "name": "Hot Mess", "subdomain": "hotmess",
                "theme": {"preset": "hotmess", "tagline": "Out tonight", "light": [{"name": "accent", "value": "#f0f"}], "dark": null}}})),
        ]))
        .mount(&server)
        .await;
    let client = service_client(&server);

    let person = client.people().await.unwrap().remove(0);
    assert!(person.global);
    let home = person.home_venue.as_ref().unwrap();
    assert_eq!(home.friends.as_ref().unwrap()[0].presence.as_deref(), Some("HERE"));
    let involvements = person.event_involvements.as_ref().unwrap();
    assert_eq!(involvements.len(), 1);
    assert_eq!(involvements[0].via.as_ref().unwrap().name.as_deref(), Some("House of Lux"));
    assert_eq!(involvements[0].event.venue.as_ref().unwrap().id, "v-1");
    assert_eq!(person.events().unwrap()[0].name.as_deref(), Some("Drag Brunch"));
    assert_eq!(person.tags.as_ref().unwrap()[0].color, None);

    let series = client.event_series(Some("l-1"), Some("v-1")).await.unwrap().remove(0);
    assert_eq!((series.duration_minutes, series.time_zone.as_deref()), (Some(180), Some("America/Denver")));
    assert_eq!(series.venue.unwrap().id, "v-1");

    assert_eq!(client.event("e-1").await.unwrap().unwrap().id, "e-1");
    assert_eq!(client.node("v-1").await.unwrap().unwrap().typename.as_deref(), Some("Venue"));
    assert!(client.me().await.unwrap().is_none());
    let near = Coordinate::new(46.87, -113.99).unwrap();
    assert_eq!(client.closest_locale(near).await.unwrap().unwrap().name.as_deref(), Some("Missoula"));
    let audience = client.audience().await.unwrap();
    let theme = audience.theme.unwrap();
    assert_eq!((audience.subdomain.as_str(), theme.light[0].value.as_str(), theme.dark.len()), ("hotmess", "#f0f", 0));
}

#[tokio::test]
async fn community_reads_everything_and_skips_missing_modules() {
    let server = MockServer::start().await;
    trade(&server, "jwt-1", 1).await;
    let no_people = json!({"errors": [{"message": "Field 'people' doesn't exist on type 'Query'", "extensions": {"code": "undefinedField"}}]});
    Mock::given(method("POST"))
        .and(path(GRAPHQL))
        .respond_with(Operations(vec![
            ("Audience", json!({"data": {"id": AUDIENCE, "name": "Hot Mess", "subdomain": "hotmess", "theme": null}})),
            ("Locales", json!({"data": {"locales": [{"id": "l-1", "name": "Missoula"}]}})),
            ("Venues", json!({"data": {"venues": {"list": {"nodes": [venue_json()]}}}})),
            ("People", no_people),
            ("SchemaFields", json!({"data": {}})),
            ("Events", json!({"data": {"events": {"list": {"nodes": [event_json()]}}}})),
            ("EventSeries", json!({"data": {"events": {"series": {"nodes": []}}}})),
        ]))
        .mount(&server)
        .await;
    let community = service_client(&server).community().await.unwrap();
    assert_eq!(community.audience.unwrap().name, "Hot Mess");
    assert_eq!(
        (community.locales.len(), community.venues.len(), community.people.len(), community.events.len()),
        (1, 1, 0, 1)
    );

    let failing = MockServer::start().await;
    trade(&failing, "jwt-1", 1).await;
    Mock::given(method("POST")).and(path(GRAPHQL)).respond_with(ResponseTemplate::new(500)).mount(&failing).await;
    assert_eq!(service_client(&failing).community().await.unwrap_err().code(), codes::INTERNAL);
}

#[tokio::test]
async fn public_listings_page_through() {
    let server = MockServer::start().await;
    trade(&server, "jwt-1", 1).await;
    Mock::given(method("GET"))
        .and(path("/v1/public/listings"))
        .and(query_param("page", "1"))
        .and(header("authorization", "Bearer jwt-1"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({"listings": [
            {"kind": "venue", "id": "v-1", "path": "/venues/v-1", "visibility": "public", "title": "The Edge",
             "description": "Bar", "address": "123 Higgins", "phone": "555", "website": "https://edge.test", "listed": true},
            {"kind": "event", "id": "e-1", "visibility": "community", "title": "Event", "description": "Sign in to see more details."}
        ], "page_count": 2, "next_page": 2})))
        .mount(&server)
        .await;
    Mock::given(method("GET"))
        .and(path("/v1/public/listings"))
        .and(query_param("page", "2"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({"listings": [
            {"kind": "event", "id": "e-2", "visibility": "public", "title": "Brunch", "start_at": "2026-11-20T18:00:00Z",
             "venue_name": "The Edge", "cover_cents": 1000, "is_canceled": false, "ticket_url": null}
        ], "page_count": 2, "next_page": null})))
        .mount(&server)
        .await;
    Mock::given(method("GET"))
        .and(path("/v1/public/events/e-2"))
        .respond_with(
            ResponseTemplate::new(200).set_body_json(json!({"kind": "event", "id": "e-2", "visibility": "public"})),
        )
        .mount(&server)
        .await;
    Mock::given(method("GET"))
        .and(path("/v1/public/venues/gone"))
        .respond_with(ResponseTemplate::new(404).set_body_json(json!({"error": "not_found"})))
        .mount(&server)
        .await;
    Mock::given(method("GET"))
        .and(path("/v1/public/venues/v-1/tonight"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({"venue": {"id": "v-1"}})))
        .mount(&server)
        .await;
    Mock::given(method("GET"))
        .and(path("/v1/public/posts/p-1"))
        .respond_with(
            ResponseTemplate::new(403)
                .set_body_json(json!({"error": "forbidden", "message": "Public site credential required"})),
        )
        .mount(&server)
        .await;

    let client = service_client(&server);
    let listings = client.public_listings().await.unwrap();
    assert_eq!(listings.len(), 3);
    assert!(listings[0].is_public() && !listings[1].is_public());
    assert_eq!((listings[0].listed, listings[0].phone.as_deref()), (Some(true), Some("555")));
    assert_eq!((listings[2].cover_cents, listings[2].venue_name.as_deref()), (Some(1000), Some("The Edge")));
    assert!(listings[2].start_at.is_some());
    assert!(client.public_listing(ListingKind::Event, "e-2").await.unwrap().unwrap().is_public());
    assert!(client.public_listing(ListingKind::Venue, "gone").await.unwrap().is_none());
    assert_eq!(client.public_listing(ListingKind::Post, "p-1").await.unwrap_err().code(), codes::FORBIDDEN);
    assert_eq!(client.public_tonight("v-1").await.unwrap()["venue"]["id"], "v-1");
}

#[tokio::test]
async fn a_session_is_sent_to_the_instance_that_issued_it_and_forgotten_when_refused() {
    let issuer = MockServer::start().await;
    let configured = MockServer::start().await;
    let credential: Credential = serde_json::from_value(json!({
        "token": "session-jwt", "userId": "u-1", "audienceId": AUDIENCE, "role": "member",
        "endpoint": format!("{}{GRAPHQL}", issuer.uri())
    }))
    .unwrap();
    Mock::given(method("POST"))
        .and(path(GRAPHQL))
        .and(header("x-audiencekit-environment", "staging"))
        .respond_with(Operations(vec![(
            "Me",
            json!({"data": {"me": {"self": {"id": "u-1", "name": "Rick M.", "firstName": "Rick", "isAdmin": true}}}}),
        )]))
        .expect(1)
        .mount(&issuer)
        .await;
    let client = Client::builder()
        .base_url(configured.uri())
        .environment(Environment::Staging)
        .session(credential.clone())
        .build()
        .unwrap();
    let me = client.me().await.unwrap().unwrap();
    assert_eq!((me.first_name.as_deref(), me.is_admin), (Some("Rick"), Some(true)));
    assert_eq!(client.credential().await.unwrap(), Some(credential.clone()));

    // A base URL that trusts the issuer gets the call instead; when it refuses the session, the client forgets it.
    Mock::given(method("POST")).and(path(GRAPHQL)).respond_with(ResponseTemplate::new(401)).mount(&configured).await;
    let trusting = Client::builder()
        .configuration(Configuration {
            base_url: configured.uri(),
            trusted_credential_origins: vec![issuer.uri()],
            ..Default::default()
        })
        .session(credential)
        .build()
        .unwrap();
    assert!(trusting.venues().await.unwrap_err().is_unauthenticated());
    assert!(trusting.credential().await.unwrap().is_none());
    assert_eq!(trusting.venues().await.unwrap_err().code(), codes::NOT_SIGNED_IN);
}

#[tokio::test]
async fn a_bearer_value_needs_an_audience_which_branding_finds() {
    let server = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/v1/branding"))
        .and(query_param("host", "hotmess.social"))
        .respond_with(
            ResponseTemplate::new(200).set_body_json(json!({"audience": {"id": AUDIENCE, "name": "Hot Mess"}})),
        )
        .expect(2) // Once to find the audience (then remembered), once asked for below.
        .mount(&server)
        .await;
    Mock::given(method("POST"))
        .and(path(GRAPHQL))
        .and(header("authorization", "Bearer app-key"))
        .respond_with(Operations(vec![("Locales", json!({"data": {"locales": [{"id": "l-1"}]}}))]))
        .mount(&server)
        .await;
    let client = Client::builder()
        .base_url(server.uri())
        .host("hotmess.social")
        .auth(Auth::from_token("app-key"))
        .build()
        .unwrap();
    assert_eq!(client.locales().await.unwrap().len(), 1);
    assert_eq!(client.locales().await.unwrap()[0].id, "l-1");
    assert!(client.credential().await.unwrap().is_none());
    let branding = client.branding(None).await.unwrap();
    assert_eq!(branding.name.as_deref(), Some("Hot Mess"));

    let unconfigured = Client::builder().base_url(server.uri()).auth(Auth::from_token("app-key")).build().unwrap();
    assert_eq!(unconfigured.locales().await.unwrap_err().code(), codes::MISSING_CONFIGURATION);
    assert_eq!(unconfigured.branding(None).await.unwrap_err().code(), codes::MISSING_CONFIGURATION);
    assert_eq!(unconfigured.branding(Some("nowhere.test")).await.unwrap_err().code(), codes::NOT_FOUND);

    let configured = Client::builder()
        .base_url(server.uri())
        .audience_id(AUDIENCE)
        .auth(Auth::Bearer("app-key".into()))
        .build()
        .unwrap();
    assert_eq!(configured.audience_id().await.unwrap(), AUDIENCE);
    configured.set_auth(Auth::None).await;
    assert_eq!(configured.venues().await.unwrap_err().code(), codes::NOT_SIGNED_IN);
}

#[tokio::test]
async fn responses_the_sdk_cannot_read() {
    let server = MockServer::start().await;
    Mock::given(method("POST"))
        .and(path(GRAPHQL))
        .respond_with(ResponseTemplate::new(200).set_body_string("<html>"))
        .mount(&server)
        .await;
    Mock::given(method("GET"))
        .and(path("/v1/public/listings"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!([])))
        .mount(&server)
        .await;
    Mock::given(method("GET"))
        .and(path("/v1/branding"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({})))
        .mount(&server)
        .await;
    let client = Client::builder()
        .base_url(server.uri())
        .audience_id(AUDIENCE)
        .host("x.test")
        .auth(Auth::Bearer("k".into()))
        .build()
        .unwrap();
    assert_eq!(client.venues().await.unwrap_err().code(), codes::DECODING);
    assert_eq!(client.public_listings_page(0).await.unwrap_err().code(), codes::DECODING);
    assert_eq!(client.branding(None).await.unwrap_err().code(), codes::DECODING);
    assert_eq!(client.request(reqwest::Method::GET, "v1/public/listings", &[], None).await.unwrap(), json!([]));

    let unreachable = Client::builder()
        .base_url("http://127.0.0.1:9")
        .audience_id(AUDIENCE)
        .auth(Auth::Bearer("k".into()))
        .build()
        .unwrap();
    let error = unreachable.venues().await.unwrap_err();
    assert_eq!(error.code(), codes::NETWORK);
    assert!(std::error::Error::source(&error).is_some());
}

#[tokio::test]
#[allow(unsafe_code)]
async fn from_env_reads_goose_style_settings() {
    let server = MockServer::start().await;
    trade(&server, "jwt-env", 1).await;
    // SAFETY: this is the only test that touches these variables.
    unsafe {
        std::env::set_var("AUDIENCEKIT_TOKEN", "akst_ab_secret");
        std::env::set_var("AUDIENCEKIT_BASE_URL", server.uri());
        std::env::set_var("AUDIENCEKIT_AUDIENCE_ID", AUDIENCE);
        std::env::set_var("AUDIENCEKIT_HOST", "hotmess.social");
    }
    let client = Client::from_env().unwrap();
    assert_eq!(client.configuration().host.as_deref(), Some("hotmess.social"));
    assert_eq!(client.credential().await.unwrap().unwrap().token, "jwt-env");
    assert!(format!("{client:?}").contains("hotmess.social"));
}
