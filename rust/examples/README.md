# Rust examples

Small programs built on the `audiencekit` crate. Each keeps its work in public functions, so the crate's tests run
them against a fake API, and runs as a program:

```sh
AUDIENCEKIT_TOKEN=… AUDIENCEKIT_HOST=hotmess.social cargo run --example news_digest -- Denver
```

| File | What it shows | Credential |
| --- | --- | --- |
| [`listings_page.rs`](listings_page.rs) | A static page of the audience's public listings, for a scheduled job to publish | A `public:read` service token |
| [`news_digest.rs`](news_digest.rs) | A Markdown digest of a locale's news and its national news, for a newsletter | An application API key |
| [`community.rs`](community.rs) | The whole community as JSON, or the public listings with `--public` | An application API key (a service token with `--public`) |
| [`graphql_documents.rs`](graphql_documents.rs) | Writes every document the client sends, for the schema check | None |
