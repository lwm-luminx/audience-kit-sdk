// What a signed-in member does on a site, in the order a night out goes: RSVP, add it to their calendar, buy cover,
// show the pass at the door, and report something they saw in chat.
import { AudienceKitClient, REPORT_REASONS, coverPassCode, secondsUntilNextCoverPassWindow, type Event } from "audience-kit";

/** Says they're going, and returns how many are going now. */
export async function goingTo(client: AudienceKitClient, event: Event): Promise<number> {
  const rsvp = await client.rsvp(event.id, "ATTENDING");
  return rsvp.count;
}

/** Links that add every event they're going to (and every event at `venueId`) to their own calendar. */
export async function calendarLinks(client: AudienceKitClient, venueId?: string) {
  const feed = venueId ? await client.followVenueInCalendar(venueId) : await client.createCalendarFeed();
  return { appleOrOutlook: feed.webcalUrl, google: feed.googleUrl };
}

/**
 * The code to show at the door for tonight's cover at a venue, and how long it's good for. It changes every 30
 * seconds, so show it as a QR code and draw it again when `refreshInSeconds` runs out; don't cache it.
 */
export async function doorPass(client: AudienceKitClient, venueId: string, now = Math.floor(Date.now() / 1000)) {
  const cover = await client.venueCover(venueId);
  const pass = cover?.tickets?.cover?.viewerAdmission;
  if (!pass?.passSecret || pass.status !== "PAID") return null;
  return { code: coverPassCode(pass.id, pass.passSecret, now), refreshInSeconds: secondsUntilNextCoverPassWindow(now) };
}

/** Reports a chat message as harassment and blocks whoever sent it. */
export async function reportHarassment(client: AudienceKitClient, messageId: string) {
  return client.reportContent("MESSAGE", messageId, { reason: REPORT_REASONS[1], block: true });
}
