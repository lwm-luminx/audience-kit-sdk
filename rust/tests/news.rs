//! Soapbox news and the examples, against a fake API (wiremock).

#[path = "../examples/listings_page.rs"]
mod listings_page;
#[path = "../examples/news_digest.rs"]
mod news_digest;

use audiencekit::{ArticleQuery, ArticleTopic, Client, PublicListing};
use serde_json::{Value, json};
use wiremock::matchers::{method, path, query_param};
use wiremock::{Mock, MockServer, Request, Respond, ResponseTemplate};

const AUDIENCE: &str = "6c1b0f7e-0000-4000-8000-000000000001";
const GRAPHQL: &str = "/v1/audience/6c1b0f7e-0000-4000-8000-000000000001/graphql";

/// Answers GraphQL by operation name, and records each request's variables.
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

async fn client_for(operations: Vec<(&'static str, Value)>) -> (MockServer, Client) {
    let server = MockServer::start().await;
    Mock::given(method("POST")).and(path(GRAPHQL)).respond_with(Operations(operations)).mount(&server).await;
    let client = Client::builder()
        .base_url(server.uri())
        .audience_id(AUDIENCE)
        .auth(audiencekit::Auth::Bearer("key".into()))
        .build()
        .unwrap();
    (server, client)
}

fn article(id: &str, title: &str) -> Value {
    json!({
        "id": id, "slug": "news", "title": title, "byline": "Sam", "kind": "NEWS", "summary": "It's big.",
        "publishedAt": "2026-11-25T12:00:00Z", "teaser": true, "canonicalUrl": "https://paper/news",
        "disclosure": "Sam tends bar there.", "publication": {"id": "p1", "name": "Paper", "trusted": true}
    })
}

fn featured(mut value: Value) -> Value {
    value["featuredNationally"] = json!(true);
    value
}

fn variables(request: &Request) -> Value {
    serde_json::from_slice::<Value>(&request.body).unwrap()["variables"].clone()
}

#[tokio::test]
async fn news_calls_read_soapbox() {
    let (server, client) = client_for(vec![
        ("Articles", json!({"data": {"soapbox": {"articles": {"nodes": [article("a1", "Bar opens"), null, {"id": "x"}]}}}})),
        (
            "ArticlesPage",
            json!({"data": {"soapbox": {"articles": {"nodes": [article("a1", "Bar opens")], "pageInfo": {"endCursor": "c2", "hasNextPage": true}}}}}),
        ),
        ("NationalArticles", json!({"data": {"soapbox": {"articles": {"nodes": [featured(article("a2", "Pride"))]}}}})),
        (
            "Article",
            json!({"data": {"soapbox": {"article": {
                "id": "a1", "slug": "news", "title": "Bar opens", "byline": "Sam", "kind": "NEWS", "body": "# Hi",
                "publication": {"id": "p1", "name": "Paper"}, "venues": [{"id": "v1", "name": "Club"}], "events": null
            }}}}),
        ),
        ("ArticlesAbout", json!({"data": {"venues": {"venue": {"articles": {"list": {"nodes": [article("a1", "Bar opens")]}}}}}})),
        (
            "Publications",
            json!({"data": {"soapbox": {"publications": [
                {"id": "p1", "name": "Paper", "locale": {"id": "L1", "name": "Denver"}, "acceptsOpEds": true},
                {"id": "p2", "name": "Blog", "person": {"id": "u1", "name": "Rae"}}
            ]}}}),
        ),
        ("Publication", json!({"data": {"soapbox": {"publication": null}}})),
    ])
    .await;

    let query =
        ArticleQuery { locale_id: Some("L1".into()), publication_id: Some("p1".into()), first: Some(5), after: None };
    let articles = client.articles(&query).await.unwrap();
    assert_eq!(articles.len(), 1);
    let first = &articles[0];
    assert_eq!((first.title.as_str(), first.publication.name.as_str(), first.teaser), ("Bar opens", "Paper", true));
    assert_eq!(first.published_at.unwrap().to_rfc3339(), "2026-11-25T12:00:00+00:00");

    let page = client.articles_page(&ArticleQuery { after: Some("c1".into()), ..Default::default() }).await.unwrap();
    assert_eq!((page.end_cursor.as_deref(), page.has_next_page, page.articles.len()), (Some("c2"), true, 1));

    let national = client.national_articles(Some("L1"), Some(3)).await.unwrap();
    assert!(national[0].featured_nationally);

    let one = client.article("a1").await.unwrap().unwrap();
    assert_eq!((one.body.as_deref(), one.venues[0].name.as_deref(), one.events.len()), (Some("# Hi"), Some("Club"), 0));

    assert_eq!(client.articles_about(ArticleTopic::Venue, "v1", Some(2)).await.unwrap().len(), 1);
    let publications = client.publications().await.unwrap();
    assert_eq!(publications.len(), 2);
    assert!(publications[0].accepts_op_eds && publications[1].person.is_some());
    let local = client.local_publications("l1").await.unwrap();
    assert_eq!(local.iter().map(|p| p.id.as_str()).collect::<Vec<_>>(), ["p1"]);
    assert!(client.publication("gone").await.unwrap().is_none());

    let sent: Vec<Value> = server.received_requests().await.unwrap().iter().map(variables).collect();
    assert_eq!(sent[0], json!({"localeId": "L1", "publicationId": "p1", "first": 5}));
    assert_eq!(sent[1], json!({"first": 20, "after": "c1"}));
    assert_eq!(sent[2], json!({"localeId": "L1", "first": 3}));
    assert_eq!(sent[4], json!({"id": "v1", "first": 2}));
}

#[tokio::test]
async fn articles_about_each_topic_and_an_audience_without_soapbox() {
    let (_server, client) = client_for(vec![
        ("ArticlesAbout", json!({"data": {"locale": {"articles": {"list": {"nodes": [article("a1", "Pride")]}}}}})),
        ("Articles", json!({"data": {"id": AUDIENCE}})),
    ])
    .await;
    assert_eq!(client.articles_about(ArticleTopic::Locale, "L1", None).await.unwrap().len(), 1);
    for topic in [ArticleTopic::Event, ArticleTopic::Person] {
        assert!(client.articles_about(topic, "x", None).await.unwrap().is_empty());
    }
    assert!(client.articles(&ArticleQuery::default()).await.unwrap().is_empty());
}

#[tokio::test]
async fn the_news_digest_example() {
    let (_server, client) = client_for(vec![
        ("Locales", json!({"data": {"locales": [{"id": "L1", "name": "Boulder"}, {"id": "L2", "name": "Denver"}]}})),
        ("Articles", json!({"data": {"soapbox": {"articles": {"nodes": [article("a1", "Bar opens")]}}}})),
        (
            "NationalArticles",
            json!({"data": {"soapbox": {"articles": {"nodes": [article("a1", "Bar opens"), article("a2", "Pride")]}}}}),
        ),
    ])
    .await;
    let digest = news_digest::digest(&client, Some("Denver")).await.unwrap();
    assert!(digest.starts_with("# Denver this week"), "{digest}");
    assert!(
        digest.contains("- **Bar opens**, Sam for Paper ([read on Paper](https://paper/news))\n  It's big.\n  _Sam")
    );
    assert!(digest.contains("## Around the country\n\n- **Pride**"));
    assert!(news_digest::digest(&client, None).await.unwrap().starts_with("# Boulder"));

    let (_server, empty) = client_for(vec![("Locales", json!({"data": {"locales": []}}))]).await;
    assert_eq!(news_digest::digest(&empty, None).await.unwrap(), "");
    let (_server, quiet) = client_for(vec![
        ("Locales", json!({"data": {"locales": [{"id": "L1"}]}})),
        ("Articles", json!({"data": {"soapbox": null}})),
        ("NationalArticles", json!({"data": {"soapbox": null}})),
    ])
    .await;
    assert_eq!(news_digest::digest(&quiet, None).await.unwrap(), "");
}

#[tokio::test]
async fn the_listings_page_example() {
    let listing = |value: Value| PublicListing::from_json(&value).unwrap();
    let venue = listing(json!({"kind": "venue", "id": "v", "title": "Club <3", "address": "1 Main"}));
    assert_eq!(listings_page::render_listing(&venue), "<h2>Club &lt;3</h2><p>1 Main</p>");
    let event = listing(
        json!({"kind": "event", "id": "e", "title": "Bingo", "venue_name": "Club", "is_canceled": true, "start_at": "2026-12-06T18:00:00Z"}),
    );
    let html = listings_page::render_listing(&event);
    assert!(html.contains("2026-12-06T18:00:00+00:00") && html.contains("<strong>Canceled</strong>"), "{html}");
    let post = listing(json!({"kind": "post", "id": "p", "title": "Hi", "description": "\"News\""}));
    assert_eq!(listings_page::render_listing(&post), "<article><h3>Hi</h3><p>&quot;News&quot;</p></article>");
    assert_eq!(listings_page::render_listing(&listing(json!({"kind": "other", "id": "x"}))), "");

    let server = MockServer::start().await;
    Mock::given(method("GET"))
        .and(path("/v1/public/listings"))
        .and(query_param("page", "1"))
        .respond_with(ResponseTemplate::new(200).set_body_json(json!({"listings": [
            {"kind": "venue", "id": "v", "title": "Club", "visibility": "public"},
            {"kind": "post", "id": "p", "title": "Members only", "visibility": "community"}
        ], "next_page": null})))
        .mount(&server)
        .await;
    let client = Client::builder()
        .base_url(server.uri())
        .audience_id(AUDIENCE)
        .auth(audiencekit::Auth::Bearer("key".into()))
        .build()
        .unwrap();
    let page = listings_page::render_page(&client).await.unwrap();
    assert!(page.contains("<h2>Club</h2>") && !page.contains("Members only"));
}
