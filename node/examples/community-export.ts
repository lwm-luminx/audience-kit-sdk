// The whole community as JSON, for a static site generator (Astro, Eleventy, Hugo) to build pages from.
//
//   AUDIENCEKIT_TOKEN=akst_… AUDIENCEKIT_HOST=hotmess.social node --experimental-strip-types community-export.ts > community.json
import {
  AudienceKitClient,
  colorFromHex,
  colorToCss,
  eventVenue,
  listingName,
  locationCoordinate,
  type Community,
} from "audience-kit";

/** The audience's accent color as CSS, from its light theme. */
function accent(community: Community): string | null {
  const hex = community.audience?.theme?.light?.find((token) => token.name === "accent")?.value;
  const color = hex ? colorFromHex(hex) : null;
  return color ? colorToCss(color) : null;
}

/** The parts a site renders, flattened: venues with a map point, events with their venue's name, and the accent color. */
export function exportCommunity(community: Community) {
  return {
    audience: community.audience?.name ?? null,
    accent: accent(community),
    locales: community.locales.map((locale) => ({ id: locale.id, name: locale.name })),
    venues: community.venues
      .filter((venue) => !venue.hidden)
      .map((venue) => ({
        id: venue.id,
        name: listingName(venue),
        locale: venue.locale?.name ?? null,
        point: locationCoordinate(venue.location),
        tags: venue.tags?.map((tag) => tag.name) ?? [],
      })),
    events: community.events.map((event) => ({ id: event.id, name: event.name, startAt: event.startAt, venue: eventVenue(event)?.name ?? null })),
  };
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const community = await AudienceKitClient.fromEnvironment().community();
  console.log(JSON.stringify(exportCommunity(community), null, 2));
}
