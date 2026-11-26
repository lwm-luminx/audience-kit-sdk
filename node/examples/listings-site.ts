// A page of the audience's public listings, as a venue guide or a city site would show them.
//
//   AUDIENCEKIT_TOKEN=akst_… AUDIENCEKIT_HOST=hotmess.social node --experimental-strip-types listings-site.ts
//
// The service token needs the `public:read` scope. Listings change a few times a day, so the page is cached for five
// minutes rather than read on every request.
import { createServer } from "node:http";
import { AudienceKitClient, isPublicListing, type PublicListing } from "audience-kit";

const escape = (text: string | null | undefined): string =>
  (text ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]!);

/** One listing as HTML: venues with their address, events with their time, posts with their text. */
export function renderListing(listing: PublicListing, timeZone = "America/Denver"): string {
  switch (listing.kind) {
    case "venue":
      return `<h2>${escape(listing.title)}</h2><p>${escape(listing.address)}</p>`;
    case "event": {
      const when = listing.start_at
        ? new Date(listing.start_at).toLocaleString("en-US", { timeZone, weekday: "short", month: "short", day: "numeric", hour: "numeric", minute: "2-digit" })
        : "";
      const canceled = listing.is_canceled ? " <strong>Canceled</strong>" : "";
      return `<h3>${escape(listing.title)}</h3><p><time>${escape(when)}</time> at ${escape(listing.venue_name)}${canceled}</p>`;
    }
    case "post":
      return `<article><h3>${escape(listing.title)}</h3><p>${escape(listing.description)}</p></article>`;
    default:
      return "";
  }
}

/** The whole page. "Community" listings show in full only to members, so they're left out of a public page. */
export async function renderPage(client: AudienceKitClient): Promise<string> {
  const listings = (await client.publicListings()).filter(isPublicListing);
  return `<!doctype html><meta charset="utf-8"><title>What's on</title>\n${listings.map((listing) => renderListing(listing)).join("\n")}\n`;
}

/** Keeps the rendered page for `seconds`, so the API is asked at most once in that time. */
export function cached(render: () => Promise<string>, seconds = 300, now = () => Date.now()): () => Promise<string> {
  let page: { html: string; until: number } | null = null;
  return async () => {
    if (page === null || now() >= page.until) page = { html: await render(), until: now() + seconds * 1000 };
    return page.html;
  };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const client = AudienceKitClient.fromEnvironment();
  const page = cached(() => renderPage(client));
  createServer(async (_request, response) => {
    try {
      response.writeHead(200, { "Content-Type": "text/html; charset=utf-8" }).end(await page());
    } catch (error) {
      console.error(error);
      response.writeHead(502).end("The listings aren't available right now.");
    }
  }).listen(8080, () => console.log("http://localhost:8080"));
}
