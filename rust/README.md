# AudienceKit for Rust

The `audiencekit` crate: an audience's locales, venues, people (DJs, performers, hosts, promoters), events and
recurring series over the AudienceKit GraphQL API (`https://api.audiencekit.com/v1/audience/<audience id>/graphql`),
plus the public listings its websites show. Async on [tokio](https://tokio.rs) and
[reqwest](https://docs.rs/reqwest) 0.13, the same stack as [goose](https://github.com/aaif-goose/goose)'s `goosed`,
so a goose build shares one copy of each.

It sends the same module-shaped documents as the Swift, Kotlin, Python and PHP SDKs in this repository (CI checks
them against [`graphql/schema.graphql`](../graphql/schema.graphql)), with the same tolerance for audiences that
haven't installed a module: when the API refuses a field (`undefinedField`), the client asks the schema which fields
the audience has and runs the call again with only those.

## Installation

Not on crates.io yet. Depend on it from this repository:

```toml
[dependencies]
audiencekit = { git = "https://github.com/lwm-luminx/audience-kit-sdk" }
```

Rust 1.85 or newer. TLS is rustls by default; `default-features = false, features = ["native-tls"]` uses the
platform's.

## Usage

```rust
use audiencekit::{Client, EventQuery, EventWindow};

// An audience service token (akst_…), minted by the audience's admins in its console. The client trades it for an
// hour-long session at POST /v1/token/service, and again before that runs out.
let client = Client::builder().service_token(std::env::var("AUDIENCEKIT_TOKEN").unwrap()).build()?;

let community = client.community().await?; // audience, locales, venues, people, upcoming events and series at once
let venues = client.venues().await?;
let past = client.events(&EventQuery { window: EventWindow::Past, first: 20, ..Default::default() }).await?;
let in_a_locale = client.events(&EventQuery { locale_id: Some(locale_id), ..Default::default() }).await?;

// The public listings (venues, events and posts as the audience's websites show them): a `public:read` token.
let listings = client.public_listings().await?;
```

`Client` is cheap to clone and safe to share across tasks (hold one in an axum `State`). Every model is
`serde::Serialize`, so a host can hand records to a model or a tool result as JSON as they are.

Other credentials: `.session(credential)` for a session the API issued to a person (it is sent to the API instance
that issued it), `.auth(Auth::Bearer(…))` for an application's API key or a bare JWT (set `.audience_id(…)` or
`.host(…)` so the client knows which audience to query). `Client::from_env()` reads `AUDIENCEKIT_TOKEN` (a token
starting `akst_` is a service token), `AUDIENCEKIT_BASE_URL`, `AUDIENCEKIT_AUDIENCE_ID` and `AUDIENCEKIT_HOST`.

Errors are one `audiencekit::Error` with a `code()` from the API's vocabulary (`UNAUTHENTICATED`, `FORBIDDEN`,
`NOT_FOUND`, `RATE_LIMITED`, …, in `audiencekit::codes`) or the SDK's own (`NETWORK`, `DECODING`,
`MISSING_CONFIGURATION`, `NOT_SIGNED_IN`), a `message()` fit to show, and the GraphQL `errors()` when there were any.

Your own documents: `client.graphql(query, variables, operation_name)` returns the response's `data`, and
`client.run(Operation::new(…))` runs a typed operation with the same schema retry.

## goose

goose reaches AudienceKit two ways, and this crate is the second:

1. **As an MCP extension**, no code: a `streamable_http` extension pointed at `https://api.audiencekit.com/v1/mcp`
   with `Authorization: Bearer <audience token>` (the plan in audience_kit_api `doc/plans/GOOSE_INTEGRATION_PLAN.md`).
2. **Natively, in goosed**, with this crate: read the community into goosed (or a goose builtin extension built on
   `rmcp`) with `Client::from_env()?.community().await?`, and keep it fresh on a schedule. `cargo run --example
   community` prints what that reads, as JSON.

Which listings a service token reads depends on its scopes. Today a `public:read` token reads the public listings
(`public_listings`, `public_listing`, `public_tonight`); the GraphQL calls (`community`, `venues`, `events`, …) need a
person's session or an application key until the API lets an agent-scoped service token read listings over GraphQL (audience_kit_api #719).

## Development

```sh
cargo test
cargo llvm-cov --fail-under-lines 85      # the repository's coverage floor (98% at 0.1.0)
cargo run --example graphql_documents -- target/graphql
node ../scripts/graphql/check.mjs --schema ../graphql/schema.graphql --endpoint consumer target/graphql
```

The crate has its own version in [`Cargo.toml`](Cargo.toml) and [`CHANGELOG.md`](CHANGELOG.md), outside the Swift and
Kotlin `VERSION`. CI is [`.github/workflows/rust.yml`](../.github/workflows/rust.yml). Once a change that raises the
version (with a `CHANGELOG.md` entry) merges to `main`, its `release` job publishes the crate to crates.io and tags the
commit `rust-<version>`.

## License

Source-available, not open source: the [AudienceKit SDK License](../LICENSE), © Love Wins Media, Inc. Use it only in
applications that connect to AudienceKit as hosted by Love Wins Media. See the repository [README](../README.md#license).
