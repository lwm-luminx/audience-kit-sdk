"""What a signed-in member does on a site, in the order a night out goes: RSVP, add it to their calendar, show the
cover pass at the door, and report something they saw in chat."""

from __future__ import annotations

import time

from audiencekit import REPORT_REASONS, Client, ReportResult, cover_pass_code
from audiencekit.cover_pass import seconds_until_next_window


def going_to(client: Client, event_id: str) -> str:
    """Says they're going, and returns their answer as the API recorded it."""
    return client.rsvp_event(event_id, "ATTENDING")


def calendar_links(client: Client, venue_id: str | None = None) -> dict[str, str]:
    """Links that add every event they're going to (and every event at ``venue_id``) to their own calendar."""
    feed = client.follow_venue_in_calendar(venue_id) if venue_id else client.create_calendar_feed()
    return {"apple_or_outlook": feed.webcal_url, "google": feed.google_url}


def door_pass(client: Client, venue_id: str, now: float | None = None) -> dict[str, object] | None:
    """The code to show at the door for tonight's cover at a venue, and how long it's good for. It changes every 30
    seconds, so show it as a QR code and draw it again when ``refresh_in_seconds`` runs out; don't cache it."""
    at = time.time() if now is None else now
    cover = client.venue_cover(venue_id)
    admission = cover.viewer_admission if cover else None
    if admission is None or not admission.pass_secret or admission.status != "PAID":
        return None
    return {
        "code": cover_pass_code(admission.id, admission.pass_secret, at),
        "refresh_in_seconds": seconds_until_next_window(at),
    }


def report_harassment(client: Client, message_id: str) -> ReportResult:
    """Reports a chat message as harassment and blocks whoever sent it."""
    return client.report_content("MESSAGE", message_id, REPORT_REASONS[1], block=True)
