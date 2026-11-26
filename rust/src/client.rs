//! The client: async, on reqwest and tokio, cheap to clone and safe to share across tasks (an axum handler in goosed,
//! for example).

use std::collections::{HashMap, HashSet};
use std::env;
use std::sync::{Arc, Mutex as SyncMutex};
use std::time::Duration;

use reqwest::{Method, Response, StatusCode};
use serde::Serialize;
use serde_json::{Value, json};
use tokio::sync::Mutex;

use crate::config::{
    API_VERSION, API_VERSION_HEADER, CLIENT_HEADER, CONSUMER_ENDPOINT, Configuration, ENVIRONMENT_HEADER, Environment,
    SDK_VERSION, endpoint_path,
};
use crate::credential::Credential;
use crate::error::{Error, GraphQLError, Result};
use crate::models::{
    Article, ArticlesPage, Audience, Branding, Coordinate, Event, EventSeries, Locale, Node, Person, PublicListing,
    PublicListingsPage, Publication, SelfUser, Venue,
};
use crate::operations::{self as ops, ArticleQuery, ArticleTopic, EventQuery, Operation};
use crate::queries;
use crate::schema::SchemaShape;

/// How a service token's session is renewed: this long before it expires.
const RENEW_BEFORE: chrono::Duration = chrono::Duration::seconds(60);

/// The credential a client sends.
#[derive(Clone, Default)]
#[allow(clippy::large_enum_variant)] // Built once per client.
pub enum Auth {
    /// None: only the calls that need no credential ([`Client::branding`]) work.
    #[default]
    None,
    /// An audience service token (`akst_<prefix>_<secret>`), minted by an admin in the audience's console. The client
    /// trades it at `POST /v1/token/service` for an hour-long session and trades it again before that runs out, or
    /// when the API refuses the session. This is the credential an agent like goose holds.
    ServiceToken(String),
    /// A session the API issued to a person (or one saved from an earlier run).
    Session(Credential),
    /// A bearer value sent as is: an application's API key, or a session JWT on its own.
    Bearer(String),
}

impl std::fmt::Debug for Auth {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(match self {
            Auth::None => "Auth::None",
            Auth::ServiceToken(_) => "Auth::ServiceToken(<redacted>)",
            Auth::Session(_) => "Auth::Session(<redacted>)",
            Auth::Bearer(_) => "Auth::Bearer(<redacted>)",
        })
    }
}

impl Auth {
    /// The credential a token names: a service token when it starts `akst_`, else a bearer value.
    pub fn from_token(token: impl Into<String>) -> Auth {
        let token = token.into();
        if token.starts_with("akst_") { Auth::ServiceToken(token) } else { Auth::Bearer(token) }
    }
}

enum AuthState {
    None,
    Service { secret: String, session: Option<Credential> },
    Session(Credential),
    Bearer(String),
}

/// What one call sends: the bearer value, and what it says about where to send it.
#[derive(Clone)]
struct Authorization {
    token: String,
    endpoint: Option<String>,
    audience_id: Option<String>,
    service: bool,
}

/// Everything the audience lists, in one go: what an agent reads in to know the community.
#[derive(Clone, Debug, Default, PartialEq, Serialize)]
pub struct Community {
    /// The audience.
    pub audience: Option<Audience>,
    /// Its locales.
    pub locales: Vec<Locale>,
    /// Its venues.
    pub venues: Vec<Venue>,
    /// The people it lists.
    pub people: Vec<Person>,
    /// Its upcoming events.
    pub events: Vec<Event>,
    /// Its recurring events.
    pub event_series: Vec<EventSeries>,
}

/// The kinds of public listing [`Client::public_listing`] reads.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum ListingKind {
    /// A venue.
    Venue,
    /// An event.
    Event,
    /// A post on the audience's website.
    Post,
}

impl ListingKind {
    fn path(self) -> &'static str {
        match self {
            ListingKind::Venue => "venues",
            ListingKind::Event => "events",
            ListingKind::Post => "posts",
        }
    }
}

struct Inner {
    http: reqwest::Client,
    configuration: Configuration,
    auth: Mutex<AuthState>,
    schema_cache: SyncMutex<HashMap<String, HashSet<String>>>,
    resolved_audience_id: SyncMutex<Option<String>>,
}

/// Talks to the AudienceKit API on behalf of one audience.
///
/// ```no_run
/// # async fn run() -> audiencekit::Result<()> {
/// let client = audiencekit::Client::builder()
///     .service_token(std::env::var("AUDIENCEKIT_TOKEN").unwrap())
///     .build()?;
/// for venue in client.venues().await? {
///     println!("{}", venue.name);
/// }
/// # Ok(()) }
/// ```
#[derive(Clone)]
pub struct Client {
    inner: Arc<Inner>,
}

impl std::fmt::Debug for Client {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Client").field("configuration", &self.inner.configuration).finish_non_exhaustive()
    }
}

/// Builds a [`Client`].
#[derive(Debug, Default)]
pub struct ClientBuilder {
    configuration: Configuration,
    auth: Auth,
    http: Option<reqwest::Client>,
}

impl ClientBuilder {
    /// Everything about where to talk to at once.
    pub fn configuration(mut self, configuration: Configuration) -> Self {
        self.configuration = configuration;
        self
    }

    /// The API's base URL; `https://api.audiencekit.com` by default.
    pub fn base_url(mut self, base_url: impl Into<String>) -> Self {
        self.configuration.base_url = base_url.into();
        self
    }

    /// The audience's host (e.g. `hotmess.social`), to look its ID up when nothing else says it.
    pub fn host(mut self, host: impl Into<String>) -> Self {
        self.configuration.host = Some(host.into());
        self
    }

    /// The audience's UUID. A service token or session already names its audience.
    pub fn audience_id(mut self, audience_id: impl Into<String>) -> Self {
        self.configuration.audience_id = Some(audience_id.into());
        self
    }

    /// Production (the default) or staging.
    pub fn environment(mut self, environment: Environment) -> Self {
        self.configuration.environment = environment;
        self
    }

    /// The credential to send.
    pub fn auth(mut self, auth: Auth) -> Self {
        self.auth = auth;
        self
    }

    /// An audience service token (`akst_…`): see [`Auth::ServiceToken`].
    pub fn service_token(self, secret: impl Into<String>) -> Self {
        self.auth(Auth::ServiceToken(secret.into()))
    }

    /// A session the API issued.
    pub fn session(self, credential: Credential) -> Self {
        self.auth(Auth::Session(credential))
    }

    /// The reqwest client to send with, for your own timeouts, proxies or connection pool. The default times out
    /// after 30 seconds.
    pub fn http_client(mut self, http: reqwest::Client) -> Self {
        self.http = Some(http);
        self
    }

    /// The client.
    pub fn build(self) -> Result<Client> {
        let http = match self.http {
            Some(http) => http,
            None => reqwest::Client::builder().timeout(Duration::from_secs(30)).build().map_err(Error::network)?,
        };
        let auth = match self.auth {
            Auth::None => AuthState::None,
            Auth::ServiceToken(secret) => AuthState::Service { secret, session: None },
            Auth::Session(credential) => AuthState::Session(credential),
            Auth::Bearer(token) => AuthState::Bearer(token),
        };
        Ok(Client {
            inner: Arc::new(Inner {
                http,
                configuration: self.configuration,
                auth: Mutex::new(auth),
                schema_cache: SyncMutex::new(HashMap::new()),
                resolved_audience_id: SyncMutex::new(None),
            }),
        })
    }
}

impl Client {
    /// A builder for a client.
    pub fn builder() -> ClientBuilder {
        ClientBuilder::default()
    }

    /// A client configured from the environment, the way goose passes an extension its secrets:
    /// `AUDIENCEKIT_TOKEN` (a service token `akst_…`, or another bearer value), and optionally
    /// `AUDIENCEKIT_BASE_URL`, `AUDIENCEKIT_AUDIENCE_ID` and `AUDIENCEKIT_HOST`.
    pub fn from_env() -> Result<Client> {
        let mut builder = Client::builder();
        if let Ok(token) = env::var("AUDIENCEKIT_TOKEN") {
            builder = builder.auth(Auth::from_token(token));
        }
        if let Ok(base_url) = env::var("AUDIENCEKIT_BASE_URL") {
            builder = builder.base_url(base_url);
        }
        if let Ok(audience_id) = env::var("AUDIENCEKIT_AUDIENCE_ID") {
            builder = builder.audience_id(audience_id);
        }
        if let Ok(host) = env::var("AUDIENCEKIT_HOST") {
            builder = builder.host(host);
        }
        builder.build()
    }

    /// Where the client talks to.
    pub fn configuration(&self) -> &Configuration {
        &self.inner.configuration
    }

    // Credentials

    /// The session the client sends: the one it was given, or the one its service token was traded for (trading it
    /// first if it hasn't yet). `None` for a bearer value or no credential. Never log its token.
    pub async fn credential(&self) -> Result<Option<Credential>> {
        let has_service_token = matches!(*self.inner.auth.lock().await, AuthState::Service { .. });
        if has_service_token {
            self.authorization(false).await?;
        }
        Ok(match &*self.inner.auth.lock().await {
            AuthState::Session(credential) => Some(credential.clone()),
            AuthState::Service { session, .. } => session.clone(),
            AuthState::None | AuthState::Bearer(_) => None,
        })
    }

    /// Replaces the credential the client sends.
    pub async fn set_auth(&self, auth: Auth) {
        let state = match auth {
            Auth::None => AuthState::None,
            Auth::ServiceToken(secret) => AuthState::Service { secret, session: None },
            Auth::Session(credential) => AuthState::Session(credential),
            Auth::Bearer(token) => AuthState::Bearer(token),
        };
        *self.inner.auth.lock().await = state;
        self.inner.schema_cache.lock().expect("schema cache").clear();
    }

    /// The bearer value for a call, trading the service token first when its session is missing, nearly over, or
    /// (`renew`) was just refused.
    async fn authorization(&self, renew: bool) -> Result<Authorization> {
        let mut auth = self.inner.auth.lock().await;
        match &mut *auth {
            AuthState::None => Err(Error::not_signed_in()),
            AuthState::Bearer(token) => {
                Ok(Authorization { token: token.clone(), endpoint: None, audience_id: None, service: false })
            }
            AuthState::Session(credential) => Ok(Authorization {
                token: credential.token.clone(),
                endpoint: Some(credential.endpoint.clone()),
                audience_id: credential.audience_id.clone(),
                service: false,
            }),
            AuthState::Service { secret, session } => {
                let current = session.as_ref().filter(|credential| !renew && !credential.expires_within(RENEW_BEFORE));
                let credential = match current {
                    Some(credential) => credential.clone(),
                    None => {
                        let traded = self.trade_service_token(secret).await?;
                        *session = Some(traded.clone());
                        traded
                    }
                };
                Ok(Authorization {
                    token: credential.token,
                    endpoint: Some(credential.endpoint),
                    audience_id: credential.audience_id,
                    service: true,
                })
            }
        }
    }

    async fn trade_service_token(&self, secret: &str) -> Result<Credential> {
        let response = self
            .send(
                Method::POST,
                &self.inner.configuration.base_url,
                "/v1/token/service",
                &[],
                Some(&json!({"service_token": secret})),
                None,
            )
            .await?;
        let status = response.status();
        let body = read_json(response).await;
        if !status.is_success() {
            if status == StatusCode::UNAUTHORIZED {
                return Err(Error::unauthorized(Some("The service token was refused: it is invalid or was revoked.")));
            }
            return Err(Error::for_status(status.as_u16(), &body));
        }
        serde_json::from_value(body).map_err(|error| Error::decoding(format!("The service session: {error}")))
    }

    /// Forgets a session the API refused, unless it has been replaced since.
    async fn session_refused(&self, token: &str) {
        let mut auth = self.inner.auth.lock().await;
        if matches!(&*auth, AuthState::Session(credential) if credential.token == token) {
            *auth = AuthState::None;
        }
    }

    // Transport

    async fn send(
        &self,
        method: Method,
        base_url: &str,
        path: &str,
        params: &[(&str, String)],
        body: Option<&Value>,
        token: Option<&str>,
    ) -> Result<Response> {
        let url = format!("{}{}", base_url.trim_end_matches('/'), path);
        let mut request = self
            .inner
            .http
            .request(method, url)
            .header("Accept", "application/json")
            .header(CLIENT_HEADER, format!("AudienceKit-Rust/{SDK_VERSION}"))
            .header(API_VERSION_HEADER, API_VERSION);
        if self.inner.configuration.environment != Environment::Production {
            request = request.header(ENVIRONMENT_HEADER, self.inner.configuration.environment.as_str());
        }
        if !params.is_empty() {
            request = request.query(params);
        }
        if let Some(token) = token {
            request = request.bearer_auth(token);
        }
        if let Some(body) = body {
            request = request.json(body);
            if let Some(query) = body.get("query").and_then(Value::as_str) {
                request = request.header("X-APOLLO-OPERATION-TYPE", operation_type(query));
            }
            if let Some(name) = body.get("operationName").and_then(Value::as_str) {
                request = request.header("X-APOLLO-OPERATION-NAME", name);
            }
        }
        request.send().await.map_err(Error::network)
    }

    /// Sends an authenticated request and returns the JSON body of a successful response. A refused service session
    /// is traded again and the call retried once; a refused person's session is forgotten.
    async fn authenticated(
        &self,
        method: Method,
        path: impl Fn(&Authorization) -> Result<String>,
        params: &[(&str, String)],
        body: Option<&Value>,
    ) -> Result<Value> {
        let mut authorization = self.authorization(false).await?;
        let mut retried = false;
        loop {
            let base = self.inner.configuration.api_base(authorization.endpoint.as_deref());
            let response = self
                .send(method.clone(), &base, &path(&authorization)?, params, body, Some(&authorization.token))
                .await?;
            let status = response.status();
            if status.is_success() {
                return Ok(read_json(response).await);
            }
            let body = read_json(response).await;
            if status == StatusCode::UNAUTHORIZED {
                if authorization.service && !retried {
                    retried = true;
                    authorization = self.authorization(true).await?;
                    continue;
                }
                self.session_refused(&authorization.token).await;
            }
            return Err(Error::for_status(status.as_u16(), &body));
        }
    }

    /// Sends an authenticated request to a REST endpoint (`/v1/…`) and returns the JSON body.
    pub async fn request(
        &self,
        method: Method,
        path: &str,
        params: &[(&str, String)],
        body: Option<&Value>,
    ) -> Result<Value> {
        let path = if path.starts_with('/') { path.to_string() } else { format!("/{path}") };
        self.authenticated(method, |_| Ok(path.clone()), params, body).await
    }

    // Branding and audience

    /// The audience's public branding for `host` (the configured one by default). No credential needed.
    pub async fn branding(&self, host: Option<&str>) -> Result<Branding> {
        let host = host
            .map(String::from)
            .or_else(|| self.inner.configuration.host.clone())
            .ok_or_else(|| Error::missing_configuration("branding needs a host"))?;
        let response = self
            .send(Method::GET, &self.inner.configuration.base_url, "/v1/branding", &[("host", host)], None, None)
            .await?;
        let status = response.status();
        let body = read_json(response).await;
        if !status.is_success() {
            return Err(Error::for_status(status.as_u16(), &body));
        }
        Branding::from_json(&body).ok_or_else(|| Error::decoding("The branding named no audience."))
    }

    /// The audience this client queries: the credential's, else the configured ID, else the one that owns the
    /// configured host (looked up once).
    pub async fn audience_id(&self) -> Result<String> {
        if let Some(known) = self.known_audience_id(None) {
            return Ok(known);
        }
        if matches!(*self.inner.auth.lock().await, AuthState::Service { .. }) {
            if let Some(audience) = self.authorization(false).await?.audience_id {
                return Ok(audience);
            }
        }
        if self.inner.configuration.host.is_none() {
            return Err(Error::missing_configuration("set an audience ID or a host"));
        }
        let found = self.branding(None).await?.audience_id;
        *self.inner.resolved_audience_id.lock().expect("audience") = Some(found.clone());
        Ok(found)
    }

    fn known_audience_id(&self, authorization: Option<&Authorization>) -> Option<String> {
        authorization
            .and_then(|authorization| authorization.audience_id.clone())
            .or_else(|| self.inner.configuration.audience_id.clone())
            .or_else(|| self.inner.resolved_audience_id.lock().expect("audience").clone())
    }

    // GraphQL

    /// Runs an operation against the audience's consumer endpoint and returns its `data`. Fails when the response
    /// carries errors, even alongside data.
    pub async fn graphql(&self, query: &str, variables: Option<&Value>, operation_name: Option<&str>) -> Result<Value> {
        self.graphql_at(CONSUMER_ENDPOINT, query, variables, operation_name).await
    }

    /// [`graphql`](Client::graphql) at another of the audience's endpoints (`staffql`, for a staff session).
    pub async fn graphql_at(
        &self,
        endpoint: &str,
        query: &str,
        variables: Option<&Value>,
        operation_name: Option<&str>,
    ) -> Result<Value> {
        let configured = self.audience_id().await.ok();
        let mut body = json!({"query": query});
        if let Some(variables) = variables {
            body["variables"] = variables.clone();
        }
        if let Some(name) = operation_name {
            body["operationName"] = json!(name);
        }
        let envelope = self
            .authenticated(
                Method::POST,
                |authorization| {
                    let audience = self
                        .known_audience_id(Some(authorization))
                        .or_else(|| configured.clone())
                        .ok_or_else(|| Error::missing_configuration("set an audience ID or a host"))?;
                    Ok(endpoint_path(&audience, endpoint))
                },
                &[],
                Some(&body),
            )
            .await?;
        graphql_data(envelope)
    }

    fn cache_prefix(audience: &str, endpoint: &str) -> String {
        format!("{audience}|{endpoint}|")
    }

    fn cached_shape(&self, prefix: &str, types: &[&str]) -> Option<SchemaShape> {
        let cache = self.inner.schema_cache.lock().expect("schema cache");
        let mut fields = HashMap::new();
        for name in types {
            fields.insert((*name).to_string(), cache.get(&format!("{prefix}{name}"))?.clone());
        }
        Some(SchemaShape::new(fields))
    }

    /// Which fields each of `types` has in the audience's schema, cached for the client.
    pub async fn schema_fields(&self, types: &[&str]) -> Result<SchemaShape> {
        let prefix = Client::cache_prefix(&self.audience_id().await?, CONSUMER_ENDPOINT);
        let missing: Vec<&str> = {
            let cache = self.inner.schema_cache.lock().expect("schema cache");
            types.iter().copied().filter(|name| !cache.contains_key(&format!("{prefix}{name}"))).collect()
        };
        if !missing.is_empty() {
            let data = self.graphql(&queries::schema_fields(&missing), None, Some("SchemaFields")).await?;
            let mut cache = self.inner.schema_cache.lock().expect("schema cache");
            for (index, name) in missing.iter().enumerate() {
                let names = data
                    .get(format!("t{index}"))
                    .and_then(|found| found.get("fields"))
                    .and_then(Value::as_array)
                    .map(|fields| {
                        fields.iter().filter_map(|field| field.get("name")?.as_str().map(String::from)).collect()
                    })
                    .unwrap_or_default();
                cache.insert(format!("{prefix}{name}"), names);
            }
        }
        Ok(self.cached_shape(&prefix, types).unwrap_or_default())
    }

    /// Runs a typed operation: first for an audience with every module; when the API refuses a field
    /// (`undefinedField`), asks the schema which fields its types have and runs it again with only those.
    pub async fn run<T>(&self, operation: Operation<T>) -> Result<T> {
        let attempt = |shape: SchemaShape| {
            let text = operation.text(&shape);
            let operation = &operation;
            async move {
                let data = self.graphql(&text, operation.variables.as_ref(), Some(&operation.name)).await?;
                operation.decode(&data)
            }
        };
        if operation.types.is_empty() {
            return attempt(SchemaShape::everything()).await;
        }
        if let Ok(audience) = self.audience_id().await {
            if let Some(known) = self.cached_shape(&Client::cache_prefix(&audience, CONSUMER_ENDPOINT), operation.types)
            {
                return attempt(known).await;
            }
        }
        match attempt(SchemaShape::everything()).await {
            Err(error) if error.is_undefined_field() => attempt(self.schema_fields(operation.types).await?).await,
            result => result,
        }
    }

    // Typed calls

    /// The audience: name, subdomain and theme.
    pub async fn audience(&self) -> Result<Audience> {
        self.run(ops::audience()).await
    }

    /// Every venue.
    pub async fn venues(&self) -> Result<Vec<Venue>> {
        self.run(ops::venues()).await
    }

    /// Every person listed: DJs, performers, hosts and promoters.
    pub async fn people(&self) -> Result<Vec<Person>> {
        self.run(ops::people()).await
    }

    /// Every locale.
    pub async fn locales(&self) -> Result<Vec<Locale>> {
        self.run(ops::locales()).await
    }

    /// The locale nearest `position`, if any is near.
    pub async fn closest_locale(&self, position: Coordinate) -> Result<Option<Locale>> {
        self.run(ops::closest_locale(position, None)).await
    }

    /// The signed-in person's profile; `None` for a service token.
    pub async fn me(&self) -> Result<Option<SelfUser>> {
        self.run(ops::me()).await
    }

    /// Any record's type, by ID.
    pub async fn node(&self, id: &str) -> Result<Option<Node>> {
        self.run(ops::node(id)).await
    }

    /// Events: upcoming (soonest first) or past (latest first), optionally in one locale or at one venue.
    pub async fn events(&self, query: &EventQuery) -> Result<Vec<Event>> {
        self.run(ops::events(query)).await
    }

    /// One event, if it exists.
    pub async fn event(&self, id: &str) -> Result<Option<Event>> {
        self.run(ops::event(id)).await
    }

    /// Recurring events, optionally in one locale or at one venue.
    pub async fn event_series(&self, locale_id: Option<&str>, venue_id: Option<&str>) -> Result<Vec<EventSeries>> {
        self.run(ops::event_series(locale_id, venue_id, 100)).await
    }

    // News (Soapbox): every call is empty, rather than failing, for an audience without Soapbox.

    /// The audience's live articles, pinned first, then newest, optionally for one locale or publication.
    pub async fn articles(&self, query: &ArticleQuery) -> Result<Vec<Article>> {
        self.run(ops::articles(query)).await
    }

    /// A page of articles, with `end_cursor` to pass as `after` for the next ("Show more").
    pub async fn articles_page(&self, query: &ArticleQuery) -> Result<ArticlesPage> {
        self.run(ops::articles_page(query)).await
    }

    /// Articles featured nationally.
    pub async fn national_articles(&self, locale_id: Option<&str>, first: Option<u32>) -> Result<Vec<Article>> {
        self.run(ops::national_articles(locale_id, first)).await
    }

    /// One article, with its Markdown body and what it is about.
    pub async fn article(&self, id: &str) -> Result<Option<Article>> {
        self.run(ops::article(id)).await
    }

    /// Live articles about a venue, event, person or locale: "In the news" on its page.
    pub async fn articles_about(&self, topic: ArticleTopic, id: &str, first: Option<u32>) -> Result<Vec<Article>> {
        self.run(ops::articles_about(topic, id, first)).await
    }

    /// The publications the audience carries.
    pub async fn publications(&self) -> Result<Vec<Publication>> {
        self.run(ops::publications()).await
    }

    /// The publications covering a locale: the "local publishers" at the top of its news.
    pub async fn local_publications(&self, locale_id: &str) -> Result<Vec<Publication>> {
        let all = self.publications().await?;
        Ok(all
            .into_iter()
            .filter(|publication| publication.locale.as_ref().is_some_and(|l| l.id.eq_ignore_ascii_case(locale_id)))
            .collect())
    }

    /// One publication.
    pub async fn publication(&self, id: &str) -> Result<Option<Publication>> {
        self.run(ops::publication(id)).await
    }

    /// Everything the audience lists: the audience, locales, venues, people, upcoming events and series, fetched at
    /// once. A part the audience doesn't have (its module isn't installed) comes back empty; any other failure fails
    /// the call.
    pub async fn community(&self) -> Result<Community> {
        let upcoming = EventQuery::default();
        let (audience, locales, venues, people, events, event_series) = tokio::join!(
            self.audience(),
            self.locales(),
            self.venues(),
            self.people(),
            self.events(&upcoming),
            self.event_series(None, None),
        );
        Ok(Community {
            audience: optional(audience)?,
            locales: optional(locales)?.unwrap_or_default(),
            venues: optional(venues)?.unwrap_or_default(),
            people: optional(people)?.unwrap_or_default(),
            events: optional(events)?.unwrap_or_default(),
            event_series: optional(event_series)?.unwrap_or_default(),
        })
    }

    // Public listings (REST, `public:read` service tokens)

    /// One page (from 1) of the audience's public listings: up to 500 venues, then events, then posts, as its
    /// websites show them. Needs a service token with the `public:read` scope.
    pub async fn public_listings_page(&self, page: u32) -> Result<PublicListingsPage> {
        let body = self.request(Method::GET, "/v1/public/listings", &[("page", page.max(1).to_string())], None).await?;
        PublicListingsPage::from_json(&body).ok_or_else(|| Error::decoding("The listings page wasn't an object."))
    }

    /// Every public listing, page by page.
    pub async fn public_listings(&self) -> Result<Vec<PublicListing>> {
        let mut listings = Vec::new();
        let mut page = 1;
        loop {
            let found = self.public_listings_page(page).await?;
            listings.extend(found.listings);
            match found.next_page {
                Some(next) if next > i64::from(page) => page = u32::try_from(next).unwrap_or(u32::MAX),
                _ => return Ok(listings),
            }
        }
    }

    /// One public listing, if it exists.
    pub async fn public_listing(&self, kind: ListingKind, id: &str) -> Result<Option<PublicListing>> {
        match self.request(Method::GET, &format!("/v1/public/{}/{id}", kind.path()), &[], None).await {
            Ok(body) => Ok(PublicListing::from_json(&body)),
            Err(error) if error.status() == Some(404) => Ok(None),
            Err(error) => Err(error),
        }
    }

    /// Tonight at a venue, as a screen facing the room shows it (`GET /v1/public/venues/<id>/tonight`).
    pub async fn public_tonight(&self, venue_id: &str) -> Result<Value> {
        self.request(Method::GET, &format!("/v1/public/venues/{venue_id}/tonight"), &[], None).await
    }
}

/// A part the audience doesn't have (its module's root field isn't in its schema) is `None`.
fn optional<T>(result: Result<T>) -> Result<Option<T>> {
    match result {
        Ok(value) => Ok(Some(value)),
        Err(error) if error.is_undefined_field() => Ok(None),
        Err(error) => Err(error),
    }
}

async fn read_json(response: Response) -> Value {
    response.bytes().await.ok().and_then(|bytes| serde_json::from_slice(&bytes).ok()).unwrap_or(Value::Null)
}

/// An operation's `data`: errors first, because a refused mutation comes back as `{"errors": […], "data": {…}}` and
/// decoding the data would hide the refusal.
fn graphql_data(envelope: Value) -> Result<Value> {
    let Value::Object(mut envelope) = envelope else {
        return Err(Error::decoding("The response wasn't a GraphQL envelope."));
    };
    if let Some(Value::Array(errors)) = envelope.get("errors") {
        if !errors.is_empty() {
            let errors: Vec<GraphQLError> =
                errors.iter().filter_map(|error| serde_json::from_value(error.clone()).ok()).collect();
            return Err(Error::graphql(errors));
        }
    }
    match envelope.remove("data") {
        Some(data @ Value::Object(_)) => Ok(data),
        _ => Err(Error::decoding("The response had no data.")),
    }
}

/// `query`, `mutation` or `subscription`: the document's first keyword.
fn operation_type(query: &str) -> &'static str {
    for token in query.replace('{', " { ").split_whitespace() {
        match token {
            "mutation" => return "mutation",
            "subscription" => return "subscription",
            "query" | "{" => return "query",
            _ => {}
        }
    }
    "query"
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn operation_types() {
        assert_eq!(operation_type("query X { a }"), "query");
        assert_eq!(operation_type("# hi\nmutation Y { b }"), "mutation");
        assert_eq!(operation_type("subscription Z { c }"), "subscription");
        assert_eq!(operation_type("{ a }"), "query");
        assert_eq!(operation_type(""), "query");
    }

    #[test]
    fn envelopes() {
        assert!(graphql_data(json!([])).is_err());
        assert!(graphql_data(json!({"data": null})).is_err());
        assert_eq!(graphql_data(json!({"data": {"a": 1}, "errors": []})).unwrap(), json!({"a": 1}));
        let error = graphql_data(
            json!({"data": {"a": null}, "errors": [{"message": "No", "extensions": {"code": "FORBIDDEN"}}]}),
        )
        .unwrap_err();
        assert_eq!(error.code(), "FORBIDDEN");
    }

    #[test]
    fn tokens_name_their_kind() {
        assert!(matches!(Auth::from_token("akst_ab_cd"), Auth::ServiceToken(_)));
        assert!(matches!(Auth::from_token("a.b.c"), Auth::Bearer(_)));
        for auth in [Auth::None, Auth::from_token("akst_x"), Auth::from_token("secret")] {
            assert!(!format!("{auth:?}").contains("secret") && !format!("{auth:?}").contains("akst_x"));
        }
        assert_eq!(ListingKind::Post.path(), "posts");
    }
}
