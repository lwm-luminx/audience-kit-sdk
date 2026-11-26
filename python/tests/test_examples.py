"""Runs the programs in ``examples/`` against the fake API, so they keep working as the SDK changes."""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Any

import httpx
import pytest

from audiencekit import Client, Configuration, Credential, PublicListing, is_cover_pass_code

from .conftest import AUDIENCE_ID, CREDENTIAL_JSON, FakeAPI

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "examples"))

import community_export
import facebook_sign_in
import listings_site
import member_actions
import news_digest

# listings_site


def test_listings_render_by_kind() -> None:
    venue = PublicListing.from_json({"kind": "venue", "id": "v", "title": "Club <3", "address": "1 Main"})
    event = PublicListing.from_json(
        {"kind": "event", "id": "e", "title": "Brunch", "venue_name": "Club", "start_at": "2026-12-06T18:00:00Z"}
    )
    canceled = PublicListing.from_json({"kind": "event", "id": "c", "title": "Bingo", "is_canceled": True})
    post = PublicListing.from_json({"kind": "post", "id": "p", "title": "Hi", "description": "News"})
    assert listings_site.render_listing(venue) == "<h2>Club &lt;3</h2><p>1 Main</p>"
    assert "Sun Dec 6, 11:00 AM" in listings_site.render_listing(event)
    assert "<strong>Canceled</strong>" in listings_site.render_listing(canceled)
    assert listings_site.render_listing(post).startswith("<article>")
    assert listings_site.render_listing(PublicListing.from_json({"kind": "other", "id": "x"})) == ""


def test_listings_page_leaves_out_community_listings_and_is_cached(client: Client, api: FakeAPI) -> None:
    api.rest["GET /v1/public/listings"] = httpx.Response(
        200,
        json={
            "listings": [
                {"kind": "venue", "id": "v", "title": "Club", "visibility": "public"},
                {"kind": "post", "id": "p", "title": "Members only", "visibility": "community"},
            ]
        },
    )
    clock = [0.0]
    page = listings_site.cached(lambda: listings_site.render_page(client), seconds=300, now=lambda: clock[0])
    html = page()
    assert "Club" in html and "Members only" not in html
    page()
    clock[0] = 301
    page()
    assert sum(1 for r in api.requests if r.url.path == "/v1/public/listings") == 2


def test_listings_app_serves_the_page_or_a_502() -> None:
    statuses: list[str] = []

    def start(status: str, headers: list[tuple[str, str]]) -> None:
        statuses.append(status)

    assert listings_site.app(lambda: "<p>hi</p>")({}, start) == [b"<p>hi</p>"]

    def broken() -> str:
        raise RuntimeError("down")

    assert listings_site.app(broken)({}, start) == [b"The listings aren't available right now."]
    assert statuses == ["200 OK", "502 Bad Gateway"]


# news_digest

ARTICLE = {
    "id": "a1",
    "slug": "news",
    "title": "Bar opens",
    "byline": "Sam",
    "kind": "NEWS",
    "summary": "It's big.",
    "teaser": True,
    "canonicalUrl": "https://paper/news",
    "disclosure": "Sam tends bar there.",
    "publication": {"id": "p1", "name": "Paper"},
}


def test_news_digest(client: Client, api: FakeAPI) -> None:
    api.operations.update(
        {
            "Locales": {"data": {"locales": [{"id": "L1", "name": "Boulder"}, {"id": "L2", "name": "Denver"}]}},
            "Articles": {"data": {"soapbox": {"articles": {"nodes": [ARTICLE]}}}},
            "NationalArticles": {
                "data": {"soapbox": {"articles": {"nodes": [ARTICLE, {**ARTICLE, "id": "a2", "title": "Pride"}]}}}
            },
        }
    )
    digest = news_digest.digest(client, "Denver")
    assert digest.startswith("# Denver this week")
    assert "- **Bar opens**, Sam for Paper ([read on Paper](https://paper/news))\n  It's big.\n  _Sam" in digest
    assert "## Around the country\n\n- **Pride**" in digest
    assert news_digest.digest(client).startswith("# Boulder")


def test_news_digest_is_empty_without_news_or_locales(client: Client, api: FakeAPI) -> None:
    api.operations.update(
        {
            "Locales": {"data": {"locales": [{"id": "L1", "name": "Denver"}]}},
            "Articles": {"data": {"soapbox": None}},
            "NationalArticles": {"data": {"soapbox": None}},
        }
    )
    assert news_digest.digest(client) == ""
    api.operations["Locales"] = {"data": {"locales": []}}
    assert news_digest.digest(client) == ""


# community_export


def test_community_export(client: Client, api: FakeAPI) -> None:
    theme = {"preset": "hotmess", "light": [{"name": "accent", "value": "#ff2d87"}], "dark": []}
    api.operations.update(
        {
            "Audience": {"data": {"id": AUDIENCE_ID, "name": "Hot Mess", "subdomain": "hotmess", "theme": theme}},
            "Locales": {"data": {"locales": [{"id": "l1", "name": "Denver"}]}},
            "Venues": {
                "data": {
                    "venues": {
                        "list": {
                            "nodes": [
                                {
                                    "id": "v1",
                                    "name": "Club",
                                    "locale": {"id": "l1", "name": "Denver"},
                                    "location": {"id": "loc", "point": "POINT (-104.98 39.74)"},
                                    "tags": [{"id": "t", "name": "Dance"}],
                                },
                                {"id": "v2", "name": "Hidden", "hidden": True},
                                {"id": "v3", "name": "Nowhere"},
                            ]
                        }
                    }
                }
            },
            "People": {"data": {"people": {"list": {"nodes": []}}}},
            "Events": {
                "data": {
                    "events": {"list": {"nodes": [{"id": "e1", "name": "Brunch", "startAt": "2026-12-06T18:00:00Z"}]}}
                }
            },
            "EventSeries": {"data": {"events": {"series": {"nodes": []}}}},
        }
    )
    exported = community_export.export_community(client.community())
    assert exported["audience"] == "Hot Mess" and exported["accent"] == "#ff2d87"
    assert [venue["id"] for venue in exported["venues"]] == ["v1", "v3"]
    assert exported["venues"][0]["point"] == {"latitude": 39.74, "longitude": -104.98}
    assert exported["venues"][0]["tags"] == ["Dance"] and exported["venues"][1]["point"] is None
    assert exported["events"][0]["start_at"] == "2026-12-06T18:00:00+00:00"


def test_community_export_without_an_audience() -> None:
    from audiencekit import Community

    empty = Community(audience=None, locales=[], venues=[], people=[], events=[], event_series=[])
    assert community_export.export_community(empty)["accent"] is None


# member_actions


def test_member_actions(client: Client, api: FakeAPI) -> None:
    admission = {"id": "adm-1", "status": "PAID", "passSecret": "c2VjcmV0"}
    feed = {"url": "https://f.ics", "webcalUrl": "webcal://f", "googleUrl": "https://g", "venues": []}
    api.operations.update(
        {
            "RSVPEvent": {"data": {"rsvpEvent": {"event": {"id": "e1", "rsvp": {"mine": "ATTENDING"}}}}},
            "CreateCalendarFeed": {"data": {"createCalendarFeed": {"calendarFeed": feed}}},
            "SetCalendarFeedVenue": {"data": {"setCalendarFeedVenue": {"calendarFeed": feed}}},
            "VenueCover": lambda r, b: {
                "data": {
                    "venues": {
                        "venue": {"id": b["variables"]["id"], "tickets": {"cover": {"viewerAdmission": admission}}}
                        if b["variables"]["id"] == "v1"
                        else None
                    }
                }
            },
            "ReportContent": {"data": {"reportContent": {"reported": True, "blocked": True}}},
        }
    )
    assert member_actions.going_to(client, "e1") == "ATTENDING"
    assert member_actions.calendar_links(client) == {"apple_or_outlook": "webcal://f", "google": "https://g"}
    member_actions.calendar_links(client, "v1")
    assert api.last_body is not None and api.last_body["variables"]["venueId"] == "v1"
    door = member_actions.door_pass(client, "v1", now=1_000_005)
    assert door is not None and is_cover_pass_code(str(door["code"])) and door["refresh_in_seconds"] == 15
    assert member_actions.door_pass(client, "gone") is None
    result = member_actions.report_harassment(client, "m1")
    assert result.reported and result.blocked


# facebook_sign_in


def call(app: Any, path: str, query: str = "", cookie: str = "") -> tuple[str, dict[str, str], bytes]:
    answer: dict[str, Any] = {}

    def start(status: str, headers: list[tuple[str, str]]) -> None:
        answer.update(status=status, headers=dict(headers))

    body = b"".join(app({"PATH_INFO": path, "QUERY_STRING": query, "HTTP_COOKIE": cookie}, start))
    return answer["status"], answer["headers"], body


def test_facebook_sign_in_flow(api: FakeAPI) -> None:
    api.rest["GET /v1/branding"] = httpx.Response(
        200, json={"audience": {"id": AUDIENCE_ID, "name": "Hot Mess"}, "facebook": {"loginConfigId": "cfg"}}
    )
    api.rest["POST /v1/token"] = httpx.Response(200, json=CREDENTIAL_JSON)
    api.operations["Me"] = {"data": {"me": {"self": {"id": "user-1", "name": "Rae"}}}}
    sessions: dict[str, facebook_sign_in.BrowserSession] = {}
    configuration = Configuration(host="hotmess.social", facebook_app_id="123", audience_id=AUDIENCE_ID)
    app = facebook_sign_in.make_app(configuration, sessions, httpx.Client(transport=api.transport()))

    status, headers, body = call(app, "/")
    assert status == "200 OK" and b"Not signed in" in body
    cookie = headers["Set-Cookie"].split(";")[0]

    status, headers, _ = call(app, "/sign-in", cookie=cookie)
    assert status == "302 Found" and "config_id=cfg" in headers["Location"] and "client_id=123" in headers["Location"]
    state = next(iter(sessions.values())).state
    assert state is not None

    status, _, body = call(app, "/auth/facebook", "code=c&state=wrong", cookie)
    assert status == "400 Bad Request"
    call(app, "/sign-in", cookie=cookie)
    state = sessions[cookie.split("=", 1)[1]].state
    status, headers, _ = call(app, "/auth/facebook", f"code=c&state={state}", cookie)
    assert status == "302 Found" and headers["Location"] == "/"
    assert api.last_body is not None and api.last_body["code"] == "c"
    new_cookie = headers["Set-Cookie"].split(";")[0]
    assert new_cookie != cookie and len(sessions) == 1
    saved = next(iter(sessions.values())).credential
    assert saved is not None and Credential.from_json(saved).token == CREDENTIAL_JSON["token"]

    status, _, body = call(app, "/", cookie=new_cookie)
    assert status == "200 OK" and b'"signed_in_as": "Rae"' in body


def test_facebook_sign_in_sends_an_ended_session_back_to_sign_in(api: FakeAPI) -> None:
    api.operations["Me"] = lambda r, b: httpx.Response(401, json={"error": "unauthorized"})
    session = facebook_sign_in.BrowserSession(credential=dict(CREDENTIAL_JSON))
    sessions = {"s": session}
    app = facebook_sign_in.make_app(Configuration(), sessions, httpx.Client(transport=api.transport()))
    status, headers, _ = call(app, "/", cookie="sid=s")
    assert status == "302 Found" and headers["Location"] == "/sign-in"
    assert session.credential is None


def test_facebook_sign_in_passes_other_errors_through(api: FakeAPI) -> None:
    api.operations["Me"] = lambda r, b: httpx.Response(500, json={"error": "internal"})
    sessions = {"s": facebook_sign_in.BrowserSession(credential=dict(CREDENTIAL_JSON))}
    app = facebook_sign_in.make_app(Configuration(), sessions, httpx.Client(transport=api.transport()))
    with pytest.raises(Exception):  # noqa: B017
        call(app, "/", cookie="sid=s")
