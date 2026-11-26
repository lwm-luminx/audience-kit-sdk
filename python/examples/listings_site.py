"""A page of the audience's public listings, as a venue guide or a city site would show them.

    AUDIENCEKIT_TOKEN=akst_… AUDIENCEKIT_HOST=hotmess.social python listings_site.py

The service token needs the ``public:read`` scope. Listings change a few times a day, so the page is cached for five
minutes rather than read on every request.
"""

from __future__ import annotations

import time
from collections.abc import Callable, Iterable
from html import escape
from wsgiref.simple_server import make_server
from zoneinfo import ZoneInfo

from audiencekit import Client, PublicListing


def render_listing(listing: PublicListing, time_zone: str = "America/Denver") -> str:
    """One listing as HTML: venues with their address, events with their time, posts with their text."""
    title = escape(listing.title or "")
    if listing.kind == "venue":
        return f"<h2>{title}</h2><p>{escape(listing.address or '')}</p>"
    if listing.kind == "event":
        when = (
            listing.start_at.astimezone(ZoneInfo(time_zone)).strftime("%a %b %-d, %-I:%M %p")
            if listing.start_at
            else ""
        )
        canceled = " <strong>Canceled</strong>" if listing.is_canceled else ""
        return f"<h3>{title}</h3><p><time>{when}</time> at {escape(listing.venue_name or '')}{canceled}</p>"
    if listing.kind == "post":
        return f"<article><h3>{title}</h3><p>{escape(listing.description or '')}</p></article>"
    return ""


def render_page(client: Client) -> str:
    """The whole page. "Community" listings show in full only to members, so they're left out of a public page."""
    listings = [listing for listing in client.public_listings() if listing.is_public]
    body = "\n".join(render_listing(listing) for listing in listings)
    return f'<!doctype html><meta charset="utf-8"><title>What\'s on</title>\n{body}\n'


def cached(
    render: Callable[[], str], seconds: float = 300, now: Callable[[], float] = time.monotonic
) -> Callable[[], str]:
    """Keeps the rendered page for ``seconds``, so the API is asked at most once in that time."""
    page: tuple[str, float] | None = None

    def read() -> str:
        nonlocal page
        if page is None or now() >= page[1]:
            page = (render(), now() + seconds)
        return page[0]

    return read


def app(page: Callable[[], str]) -> Callable[..., Iterable[bytes]]:
    """A WSGI app serving the page; any WSGI server (gunicorn, uWSGI) runs it."""

    def serve(environ: dict[str, object], start_response: Callable[..., object]) -> Iterable[bytes]:
        try:
            html = page()
        except Exception as error:  # shown as a 502 and logged for the operator
            print(error)
            start_response("502 Bad Gateway", [("Content-Type", "text/plain; charset=utf-8")])
            return [b"The listings aren't available right now."]
        start_response("200 OK", [("Content-Type", "text/html; charset=utf-8")])
        return [html.encode()]

    return serve


if __name__ == "__main__":
    client = Client.from_environment()
    print("http://localhost:8080")
    make_server("", 8080, app(cached(lambda: render_page(client)))).serve_forever()
