//! A static page of the audience's public listings, for a venue guide or a city site to publish on a schedule (a
//! cron job, a CI workflow) rather than reading the API on every request.
//!
//! ```sh
//! AUDIENCEKIT_TOKEN=akst_… cargo run --example listings_page > public/index.html
//! ```
//!
//! The service token needs the `public:read` scope.

use audiencekit::{Client, PublicListing};

/// Text made safe to put in HTML.
pub fn escape(text: &str) -> String {
    text.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;").replace('\'', "&#39;")
}

/// One listing as HTML: venues with their address, events with their time, posts with their text.
pub fn render_listing(listing: &PublicListing) -> String {
    let title = escape(listing.title.as_deref().unwrap_or_default());
    match listing.kind.as_str() {
        "venue" => format!("<h2>{title}</h2><p>{}</p>", escape(listing.address.as_deref().unwrap_or_default())),
        "event" => {
            let when = listing.start_at.map(|at| at.to_rfc3339()).unwrap_or_default();
            let canceled = if listing.is_canceled == Some(true) { " <strong>Canceled</strong>" } else { "" };
            let venue = escape(listing.venue_name.as_deref().unwrap_or_default());
            format!("<h3>{title}</h3><p><time datetime=\"{when}\">{when}</time> at {venue}{canceled}</p>")
        }
        "post" => {
            format!(
                "<article><h3>{title}</h3><p>{}</p></article>",
                escape(listing.description.as_deref().unwrap_or_default())
            )
        }
        _ => String::new(),
    }
}

/// The whole page. "Community" listings show in full only to members, so they're left out of a public page.
pub async fn render_page(client: &Client) -> audiencekit::Result<String> {
    let listings = client.public_listings().await?;
    let body: Vec<String> = listings.iter().filter(|listing| listing.is_public()).map(render_listing).collect();
    Ok(format!("<!doctype html><meta charset=\"utf-8\"><title>What's on</title>\n{}\n", body.join("\n")))
}

#[allow(dead_code)]
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    print!("{}", render_page(&Client::from_env()?).await?);
    Ok(())
}
