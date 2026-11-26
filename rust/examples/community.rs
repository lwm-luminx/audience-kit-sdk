//! Prints an audience's community (its audience, locales, venues, people, upcoming events and series) as JSON, the
//! way goosed or any other agent host would read it in. Configured from the environment, as goose passes an
//! extension its secrets:
//!
//! ```sh
//! AUDIENCEKIT_TOKEN=<application API key> AUDIENCEKIT_HOST=hotmess.social cargo run --example community > community.json
//! ```
//!
//! With `--public`, prints the public listings instead (venues, events and posts as the audience's websites show
//! them), which a `public:read` service token reads.

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = audiencekit::Client::from_env()?;
    let json = if std::env::args().any(|argument| argument == "--public") {
        serde_json::to_string_pretty(&client.public_listings().await?)?
    } else {
        serde_json::to_string_pretty(&client.community().await?)?
    };
    println!("{json}");
    Ok(())
}
