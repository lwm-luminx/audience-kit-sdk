//! # AudienceKit SDK for Rust
//!
//! Reads an [AudienceKit](https://audiencekit.com) audience's community: its locales, venues, people (DJs,
//! performers, hosts, promoters), events and recurring series, over the audience's GraphQL API, plus the public
//! listings its websites show, and its Soapbox news. Built for agents and servers such as goose's `goosed`: async on tokio and reqwest, a
//! [`Client`] that is cheap to clone and share, and models that serialize straight to JSON.
//!
//! ```no_run
//! # async fn run() -> audiencekit::Result<()> {
//! use audiencekit::{Client, EventQuery};
//!
//! // An application API key from the audience's console. (A service token, akst_…, reads the public listings.)
//! let client = Client::builder().host("hotmess.social").auth(audiencekit::Auth::Bearer("…".into())).build()?;
//! let community = client.community().await?;
//! println!("{} venues, {} upcoming events", community.venues.len(), community.events.len());
//!
//! let tonight = client.events(&EventQuery { first: 20, ..Default::default() }).await?;
//! # Ok(()) }
//! ```
//!
//! The documents are the same module-shaped ones every AudienceKit SDK sends ([`queries`]): an audience that hasn't
//! installed a module (Facebook Pages, Google Places, RSVP, Ticketing, Friends…) has no such fields, so the client
//! asks the schema which fields are there and runs the call again without the others.
//!
//! Source-available under the AudienceKit SDK License: use it only with AudienceKit as hosted by Love Wins Media,
//! Inc. See the repository's LICENSE.

pub mod client;
pub mod config;
pub mod credential;
pub mod error;
pub mod models;
pub mod operations;
pub mod queries;
pub mod schema;

pub use client::{Auth, Client, ClientBuilder, Community, ListingKind};
pub use config::{Configuration, Environment};
pub use credential::Credential;
pub use error::{Error, GraphQLError, Result, codes};
pub use models::*;
pub use operations::{ArticleQuery, ArticleTopic, Document, EventQuery, EventWindow, Operation};
pub use schema::SchemaShape;
