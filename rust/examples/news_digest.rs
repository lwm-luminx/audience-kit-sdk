//! A Markdown digest of a locale's news, for a newsletter or a Discord post.
//!
//! ```sh
//! AUDIENCEKIT_TOKEN=<application API key> AUDIENCEKIT_HOST=hotmess.social cargo run --example news_digest -- Denver
//! ```
//!
//! Prints nothing for an audience without Soapbox, rather than failing.

use audiencekit::{Article, ArticleQuery, Client};

/// One article as a Markdown list item. A teaser carries only the start: the rest is on the publication's site.
pub fn line(article: &Article) -> String {
    let name = &article.publication.name;
    let mut text = format!("- **{}**, {} for {name}", article.title, article.byline);
    if let (true, Some(url)) = (article.teaser, &article.canonical_url) {
        text.push_str(&format!(" ([read on {name}]({url}))"));
    }
    if let Some(summary) = &article.summary {
        text.push_str(&format!("\n  {summary}"));
    }
    if let Some(disclosure) = &article.disclosure {
        text.push_str(&format!("\n  _{disclosure}_"));
    }
    text
}

/// The digest for the locale named `locale_name` (or the audience's first): its news, then the national news.
pub async fn digest(client: &Client, locale_name: Option<&str>) -> audiencekit::Result<String> {
    let locales = client.locales().await?;
    let Some(locale) = locales.iter().find(|l| l.name.as_deref() == locale_name).or(locales.first()) else {
        return Ok(String::new());
    };
    let query = ArticleQuery { locale_id: Some(locale.id.clone()), first: Some(10), ..Default::default() };
    let (local, national) =
        tokio::try_join!(client.articles(&query), client.national_articles(Some(&locale.id), Some(5)))?;
    let mut sections = vec![format!("# {} this week", locale.name.as_deref().unwrap_or("Your city"))];
    if !local.is_empty() {
        sections.push(format!("## Local news\n\n{}", local.iter().map(line).collect::<Vec<_>>().join("\n")));
    }
    let elsewhere: Vec<String> =
        national.iter().filter(|article| !local.iter().any(|seen| seen.id == article.id)).map(line).collect();
    if !elsewhere.is_empty() {
        sections.push(format!("## Around the country\n\n{}", elsewhere.join("\n")));
    }
    Ok(if sections.len() > 1 { format!("{}\n", sections.join("\n\n")) } else { String::new() })
}

#[allow(dead_code)]
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let client = Client::from_env()?;
    print!("{}", digest(&client, std::env::args().nth(1).as_deref()).await?);
    Ok(())
}
