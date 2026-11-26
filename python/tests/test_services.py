"""Service tokens, the public listings, the community, news, cover, chat, the calendar and moderation."""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

import httpx
import pytest

from audiencekit import (
    REPORT_REASONS,
    AsyncClient,
    AudienceKitError,
    Client,
    Configuration,
    DeviceDescription,
    cover_pass_code,
    is_cover_pass_code,
)
from audiencekit.cover_pass import seconds_until_next_window

from .conftest import AUDIENCE_ID, ENDPOINT, FakeAPI, undefined_field

DEVICE = DeviceDescription("server-1")


def _later(seconds: float) -> str:
    return (datetime.now(timezone.utc) + timedelta(seconds=seconds)).isoformat().replace("+00:00", "Z")


def service_session(token: str, expires_in: float = 3600) -> dict[str, Any]:
    return {
        "token": token,
        "userId": None,
        "audienceId": AUDIENCE_ID,
        "role": "service",
        "expiresAt": _later(expires_in),
    }


AUDIENCE = {"data": {"id": AUDIENCE_ID, "name": "Hot Mess", "subdomain": "hotmess"}}


def env_client(api: FakeAPI, token: str, **extra: str) -> Client:
    environment = {"AUDIENCEKIT_TOKEN": token, "AUDIENCEKIT_AUDIENCE_ID": AUDIENCE_ID, **extra}
    return Client.from_environment(environment, http=httpx.Client(transport=api.transport()))


# Service tokens


def test_from_environment_trades_a_service_token_before_the_first_call(api: FakeAPI) -> None:
    api.rest["POST /v1/token/service"] = httpx.Response(200, json=service_session("svc-1"))
    api.operations["Audience"] = AUDIENCE
    client = env_client(api, "akst_a_b", AUDIENCEKIT_HOST="hotmess.social", AUDIENCEKIT_ENVIRONMENT="staging")
    assert client.configuration.environment == "staging"
    assert client.audience().name == "Hot Mess"
    assert api.requests[0].url.path == "/v1/token/service"
    assert api.bodies[0] == {"service_token": "akst_a_b"}
    assert "authorization" not in api.requests[0].headers
    assert api.last.headers["authorization"] == "Bearer svc-1"
    assert client.credential is not None and client.credential.is_service and client.credential.user_id is None


def test_from_environment_sends_another_token_as_is(api: FakeAPI) -> None:
    api.operations["Audience"] = AUDIENCE
    client = env_client(api, "app-key", AUDIENCEKIT_BASE_URL="https://api.audiencekit.com")
    client.audience()
    assert len(api.requests) == 1
    assert api.last.headers["authorization"] == "Bearer app-key"
    assert client.credential is not None and client.credential.role == "bearer"


def test_from_environment_reads_os_environ(monkeypatch: pytest.MonkeyPatch) -> None:
    monkeypatch.delenv("AUDIENCEKIT_TOKEN", raising=False)
    monkeypatch.setenv("AUDIENCEKIT_HOST", "hotmess.social")
    client = Client.from_environment()
    assert client.configuration.host == "hotmess.social"
    assert not client.is_signed_in


def test_a_service_session_is_traded_again_before_it_runs_out_and_after_a_refusal(api: FakeAPI) -> None:
    trades: list[int] = []
    refuse = {"next": False}

    def trade(request: httpx.Request, body: Any) -> httpx.Response:
        trades.append(1)
        return httpx.Response(200, json=service_session(f"svc-{len(trades)}", 30 if len(trades) == 1 else 3600))

    def audience(request: httpx.Request, body: Any) -> Any:
        if refuse["next"]:
            refuse["next"] = False
            return httpx.Response(401, json={"error": "unauthorized"})
        return AUDIENCE

    api.rest["POST /v1/token/service"] = trade
    api.operations["Audience"] = audience
    client = Client(Configuration(audience_id=AUDIENCE_ID), http=httpx.Client(transport=api.transport()))
    assert client.use_service_token("akst_x").token == "svc-1"
    client.audience()
    assert len(trades) == 2 and api.last.headers["authorization"] == "Bearer svc-2"
    refuse["next"] = True
    client.audience()
    assert len(trades) == 3 and api.last.headers["authorization"] == "Bearer svc-3"


def test_a_revoked_service_token_raises_unauthenticated(api: FakeAPI) -> None:
    api.rest["POST /v1/token/service"] = httpx.Response(401, json={"error": "unauthorized"})
    client = Client(Configuration(audience_id=AUDIENCE_ID), http=httpx.Client(transport=api.transport()))
    with pytest.raises(AudienceKitError) as raised:
        client.use_service_token("akst_revoked")
    assert raised.value.code == "UNAUTHENTICATED" and "service token" in str(raised.value)
    with pytest.raises(AudienceKitError) as again:
        client.audience()
    assert again.value.code == "NOT_SIGNED_IN"


@pytest.mark.parametrize(
    ("answer", "code"),
    [(httpx.Response(500, json={}), "INTERNAL"), (httpx.Response(200, json={"nope": 1}), "DECODING")],
)
def test_service_trade_failures(api: FakeAPI, answer: httpx.Response, code: str) -> None:
    api.rest["POST /v1/token/service"] = answer
    client = Client(Configuration(), http=httpx.Client(transport=api.transport()))
    with pytest.raises(AudienceKitError) as raised:
        client.use_service_token("akst_x")
    assert raised.value.code == code


def test_signing_out_forgets_the_service_token(api: FakeAPI) -> None:
    api.rest["POST /v1/token/service"] = httpx.Response(200, json=service_session("svc"))
    api.rest["DELETE /v1/token"] = httpx.Response(204)
    client = Client(Configuration(audience_id=AUDIENCE_ID), http=httpx.Client(transport=api.transport()))
    client.use_service_token("akst_x")
    client.sign_out()
    with pytest.raises(AudienceKitError):
        client.audience()


async def test_async_service_tokens_trade_once_for_calls_made_together(api: FakeAPI) -> None:
    trades: list[int] = []

    def trade(request: httpx.Request, body: Any) -> httpx.Response:
        trades.append(1)
        return httpx.Response(200, json=service_session("svc"))

    api.rest["POST /v1/token/service"] = trade
    api.operations["Venues"] = {"data": {"venues": {"list": {"nodes": [{"id": "v1", "name": "Club"}]}}}}
    environment = {"AUDIENCEKIT_TOKEN": "akst_a", "AUDIENCEKIT_AUDIENCE_ID": AUDIENCE_ID}
    async with AsyncClient.from_environment(environment, http=httpx.AsyncClient(transport=api.transport())) as client:
        import asyncio

        results = await asyncio.gather(client.venues(), client.venues(), client.venues())
        assert [len(r) for r in results] == [1, 1, 1]
        assert len(trades) == 1
        assert (await client.use_service_token("akst_b")).token == "svc"


async def test_async_service_session_is_traded_again_after_a_refusal(api: FakeAPI) -> None:
    trades: list[int] = []
    refuse = {"next": True}

    def trade(request: httpx.Request, body: Any) -> httpx.Response:
        trades.append(1)
        return httpx.Response(200, json=service_session(f"svc-{len(trades)}"))

    def listings(request: httpx.Request, body: Any) -> httpx.Response:
        if refuse["next"]:
            refuse["next"] = False
            return httpx.Response(401, json={})
        return httpx.Response(200, json={"listings": [], "next_page": None})

    api.rest["POST /v1/token/service"] = trade
    api.rest["GET /v1/public/listings"] = listings
    client = AsyncClient(Configuration(audience_id=AUDIENCE_ID), http=httpx.AsyncClient(transport=api.transport()))
    await client.use_service_token("akst_x")
    assert await client.public_listings() == []
    assert len(trades) == 2


# Sign-in


def test_google_review_and_apple_sign_in(anonymous: Client, api: FakeAPI) -> None:
    session = {"token": "t", "userId": "u", "audienceId": AUDIENCE_ID, "role": "member", "endpoint": ENDPOINT}
    for path in ("/v1/token/google", "/v1/token/review", "/v1/token/apple", "/v1/token/refresh"):
        api.rest[f"POST {path}"] = httpx.Response(200, json=session)
    anonymous.sign_in_with_google("id-token", DEVICE, access_token="at")
    assert api.last_body == {
        "id_token": "id-token",
        "device": {"identifier": "server-1", "type": "python"},
        "access_token": "at",
        "host": "hotmess.social",
    }
    anonymous.connect_google("id-2", DEVICE)
    assert api.last_body is not None and api.last_body["connect"] is True
    assert api.last.headers["authorization"] == "Bearer t"
    anonymous.sign_in_with_review_code("  REVIEW-1 ", DEVICE)
    assert api.last_body is not None and api.last_body["code"] == "REVIEW-1"
    anonymous.sign_in_with_apple("apple", DEVICE, authorization_code="c", redirect_uri="https://x/cb", nonce="n")
    assert api.last_body is not None and api.last_body["authorization_code"] == "c" and api.last_body["nonce"] == "n"
    assert anonymous.refresh_session().token == "t"


async def test_async_sign_in(api: FakeAPI) -> None:
    session = {"token": "t", "userId": "u", "audienceId": AUDIENCE_ID, "role": "member", "endpoint": ENDPOINT}
    for path in ("/v1/token/google", "/v1/token/review", "/v1/token/apple", "/v1/token/refresh"):
        api.rest[f"POST {path}"] = httpx.Response(200, json=session)
    client = AsyncClient(Configuration(host="hotmess.social"), http=httpx.AsyncClient(transport=api.transport()))
    await client.sign_in_with_google("id", DEVICE, name="Sam")
    await client.connect_google("id", DEVICE)
    await client.sign_in_with_review_code("R", DEVICE)
    await client.sign_in_with_apple("apple", DEVICE, first_name="Sam")
    assert (await client.refresh_session()).user_id == "u"


def test_refresh_needs_a_credential_back(client: Client, api: FakeAPI) -> None:
    api.rest["POST /v1/token/refresh"] = httpx.Response(200, json=[])
    with pytest.raises(AudienceKitError):
        client.refresh_session()


# Public listings

VENUE = {"kind": "venue", "id": "v1", "title": "Club", "visibility": "public", "listed": True, "cover_cents": 500}
EVENT = {"kind": "event", "id": "e1", "title": "Brunch", "visibility": "community", "start_at": "2026-12-06T18:00:00Z"}


def test_public_listings_read_every_page(client: Client, api: FakeAPI) -> None:
    def page(request: httpx.Request, body: Any) -> httpx.Response:
        if request.url.params["page"] == "1":
            return httpx.Response(200, json={"listings": [VENUE], "page_count": "2", "next_page": 2})
        return httpx.Response(200, json={"listings": [EVENT, "junk"], "page_count": 2, "next_page": None})

    api.rest["GET /v1/public/listings"] = page
    listings = client.public_listings()
    assert [listing.id for listing in listings] == ["v1", "e1"]
    assert [listing.is_public for listing in listings] == [True, False]
    assert listings[0].cover_cents == 500 and listings[0].listed is True
    assert listings[1].start_at == datetime(2026, 12, 6, 18, tzinfo=timezone.utc)


def test_public_listing_pages_tolerate_odd_answers(client: Client, api: FakeAPI) -> None:
    api.rest["GET /v1/public/listings"] = httpx.Response(
        200, json={"listings": [VENUE], "next_page": 1, "page_count": True}
    )
    page = client.public_listings_page(0)
    assert page.page_count == 1 and page.next_page == 1
    assert api.last.url.params["page"] == "1"
    assert len(client.public_listings()) == 1


def test_one_public_listing_and_tonight(client: Client, api: FakeAPI) -> None:
    api.rest["GET /v1/public/events/e 1"] = httpx.Response(200, json=EVENT)
    api.rest["GET /v1/public/posts/gone"] = httpx.Response(404, json={"error": "not_found"})
    api.rest["GET /v1/public/venues/v1"] = httpx.Response(403, json={"error": "forbidden"})
    api.rest["GET /v1/public/venues/v1/tonight"] = httpx.Response(200, json={"event": {"name": "Karaoke"}})
    found = client.public_listing("event", "e 1")
    assert found is not None and found.title == "Brunch"
    assert client.public_listing("post", "gone") is None
    with pytest.raises(AudienceKitError):
        client.public_listing("venue", "v1")
    with pytest.raises(ValueError):
        client.public_listing("place", "x")
    assert client.public_tonight("v1") == {"event": {"name": "Karaoke"}}


async def test_async_public_listings(async_client: AsyncClient, api: FakeAPI) -> None:
    api.rest["GET /v1/public/listings"] = httpx.Response(200, json={"listings": [VENUE], "next_page": None})
    api.rest["GET /v1/public/venues/v1"] = httpx.Response(200, json=VENUE)
    api.rest["GET /v1/public/posts/p"] = httpx.Response(404, json={})
    api.rest["GET /v1/public/events/e"] = httpx.Response(500, json={})
    api.rest["GET /v1/public/venues/v1/tonight"] = httpx.Response(200, json=[])
    assert len(await async_client.public_listings()) == 1
    assert (await async_client.public_listing("venue", "v1")) is not None
    assert await async_client.public_listing("post", "p") is None
    with pytest.raises(AudienceKitError):
        await async_client.public_listing("event", "e")
    assert await async_client.public_tonight("v1") == {}


# The community


def community_api(api: FakeAPI) -> None:
    api.operations.update(
        {
            "Audience": AUDIENCE,
            "Locales": {"data": {"locales": [{"id": "l1", "name": "Denver"}]}},
            "Venues": {"data": {"venues": {"list": {"nodes": [{"id": "v1", "name": "Club"}]}}}},
            "People": undefined_field("people", "Audience"),
            "Events": {"data": {"events": {"list": {"nodes": [{"id": "e1", "name": "Brunch"}]}}}},
            "EventSeries": {"data": {"events": {"series": {"nodes": []}}}},
        }
    )


def test_community_leaves_out_what_the_audience_doesnt_have(client: Client, api: FakeAPI) -> None:
    community_api(api)
    community = client.community()
    assert community.audience is not None and community.audience.name == "Hot Mess"
    assert [v.id for v in community.venues] == ["v1"] and len(community.locales) == 1 and len(community.events) == 1
    assert community.people == [] and community.event_series == []


async def test_async_community(async_client: AsyncClient, api: FakeAPI) -> None:
    community_api(api)
    community = await async_client.community()
    assert community.people == [] and len(community.venues) == 1


def test_community_passes_other_errors_through(client: Client, api: FakeAPI) -> None:
    api.operations["Audience"] = httpx.Response(500, json={})
    with pytest.raises(AudienceKitError):
        client.community()


async def test_async_community_passes_other_errors_through(async_client: AsyncClient, api: FakeAPI) -> None:
    community_api(api)
    api.operations["Venues"] = httpx.Response(500, json={})
    with pytest.raises(AudienceKitError):
        await async_client.community()


# News

ARTICLE = {
    "id": "a1",
    "slug": "news",
    "title": "News",
    "byline": "Sam",
    "kind": "NEWS",
    "publishedAt": "2026-11-25T12:00:00Z",
    "teaser": True,
    "canonicalUrl": "https://paper/news",
    "publication": {"id": "p1", "name": "Paper", "trusted": True, "acceptsOpEds": True},
}
PUBLICATION = {"id": "p1", "name": "Paper", "locale": {"id": "L1", "name": "Denver"}, "adFreeTipCents": 300}


def news_api(api: FakeAPI) -> None:
    api.operations.update(
        {
            "Articles": {"data": {"soapbox": {"articles": {"nodes": [ARTICLE, None]}}}},
            "NationalArticles": {
                "data": {"soapbox": {"articles": {"nodes": [{**ARTICLE, "featuredNationally": True}]}}}
            },
            "ArticlesPage": {
                "data": {
                    "soapbox": {"articles": {"nodes": [ARTICLE], "pageInfo": {"endCursor": "c2", "hasNextPage": True}}}
                }
            },
            "Article": {
                "data": {"soapbox": {"article": {**ARTICLE, "body": "# Hi", "venues": [{"id": "v1", "name": "Club"}]}}}
            },
            "ArticlesAbout": {"data": {"venues": {"venue": {"articles": {"list": {"nodes": [ARTICLE]}}}}}},
            "Publications": {
                "data": {"soapbox": {"publications": [PUBLICATION, {**PUBLICATION, "id": "p2", "locale": None}]}}
            },
            "Publication": {"data": {"soapbox": {"publication": PUBLICATION}}},
            "MyOpEds": {"data": {"soapbox": {"myOpEds": [{**ARTICLE, "status": "SUBMITTED"}]}}},
            "SubmitOpEd": {"data": {"submitOpEd": {"article": {**ARTICLE, "status": "SUBMITTED"}}}},
        }
    )


def test_news(client: Client, api: FakeAPI) -> None:
    news_api(api)
    articles = client.articles(locale_id="l1", first=5)
    assert len(articles) == 1 and articles[0].teaser and articles[0].publication.trusted
    assert api.last_body is not None and api.last_body["variables"] == {"localeId": "l1", "first": 5}
    assert client.national_articles()[0].featured_nationally
    assert api.last_body is not None and "variables" not in api.last_body
    page = client.articles_page(after="c1")
    assert page.end_cursor == "c2" and page.has_next_page and len(page.articles) == 1
    article = client.article("a1")
    assert article is not None and article.body == "# Hi" and article.venues[0].name == "Club"
    assert len(client.articles_about("venue", "v1", 3)) == 1
    assert [p.id for p in client.local_publications("l1")] == ["p1"]
    found = client.publication("p1")
    assert found is not None and found.locale is not None and found.ad_free_tip_cents == 300
    assert client.my_op_eds()[0].status == "SUBMITTED"
    assert client.submit_op_ed("p1", "T", "B").status == "SUBMITTED"
    assert api.last_body is not None and api.last_body["variables"]["summary"] is None
    with pytest.raises(ValueError):
        client.articles_about("planet", "x")


async def test_async_news(async_client: AsyncClient, api: FakeAPI) -> None:
    news_api(api)
    assert len(await async_client.articles()) == 1
    assert len(await async_client.national_articles()) == 1
    assert (await async_client.articles_page()).has_next_page
    assert await async_client.article("a1") is not None
    assert len(await async_client.articles_about("venue", "v1")) == 1
    assert len(await async_client.local_publications("L1")) == 1
    assert await async_client.publication("p1") is not None
    assert len(await async_client.my_op_eds()) == 1
    assert (await async_client.submit_op_ed("p1", "T", "B", summary="S")).id == "a1"


def test_news_is_empty_without_soapbox(client: Client, api: FakeAPI) -> None:
    for name in ("Articles", "ArticlesPage", "NationalArticles", "Article", "Publications", "Publication", "MyOpEds"):
        api.operations[name] = {"data": {"id": AUDIENCE_ID}}
    api.operations["ArticlesAbout"] = {"data": {"id": AUDIENCE_ID}}
    assert client.articles() == [] and client.national_articles() == [] and client.my_op_eds() == []
    assert client.articles_page().articles == [] and client.article("a") is None
    assert client.publications() == [] and client.publication("p") is None
    assert client.articles_about("locale", "l") == []


# Members: RSVP, cover, chat

ADMISSION = {
    "id": "adm-1",
    "status": "PAID",
    "kind": "COVER",
    "quantity": 1,
    "claimCheckNumber": 12,
    "amount": {"cents": 1000, "currency": "usd"},
    "passSecret": "c2VjcmV0",
    "venue": {"id": "v1", "name": "Club"},
    "event": {"id": "e1", "name": "Brunch"},
}
CHARGE = {
    "amount": {"cents": 1000, "currency": "usd"},
    "fee": {"cents": 50, "currency": "usd"},
    "total": {"cents": 1050, "currency": "usd"},
    "night": "2026-12-06",
    "payable": True,
    "coatCheck": {"amount": {"cents": 300, "currency": "usd"}, "night": "2026-12-06", "payable": True},
    "scale": {"min": {"cents": 500, "currency": "usd"}, "max": {"cents": 2000, "currency": "usd"}},
}
PURCHASE = {"admission": ADMISSION, "provider": "SQUARE", "squareLocationId": "L"}


def member_api(api: FakeAPI) -> None:
    api.operations.update(
        {
            "CancelRSVP": {"data": {"cancelRsvp": {"event": {"id": "e1", "rsvp": {"mine": "UNSURE", "count": 3}}}}},
            "VenueCover": lambda r, b: {
                "data": {
                    "venues": {
                        "venue": None
                        if b["variables"]["id"] == "gone"
                        else {"id": "v1", "tickets": {"cover": {"charge": CHARGE, "viewerAdmission": ADMISSION}}}
                    }
                }
            },
            "BuyCover": {"data": {"buyCover": PURCHASE}},
            "BuyCoatCheck": {"data": {"buyCoatCheck": PURCHASE}},
            "PayCover": {"data": {"payCover": {"admission": ADMISSION}}},
            "ConfirmCover": {"data": {"confirmCover": {"admission": ADMISSION}}},
            "RefundAdmission": {"data": {"refundAdmission": {"admission": {**ADMISSION, "status": "REFUNDED"}}}},
            "Admissions": {"data": {"me": {"cover": {"admissions": {"nodes": [ADMISSION]}}}}},
            "SendMyChatMessage": {
                "data": {
                    "sendMyChatMessage": {"message": {"id": "m1", "message": "hi", "sentAt": "2026-11-25T12:00:00Z"}}
                }
            },
            "RemoveMyChatMessage": {"data": {"removeMyChatMessage": {"deletedId": "m1"}}},
        }
    )


def test_rsvp_cover_and_chat(client: Client, api: FakeAPI) -> None:
    member_api(api)
    assert client.cancel_rsvp("e1").count == 3
    cover = client.venue_cover("v1")
    assert cover is not None and cover.charge is not None and cover.charge.is_sliding_scale
    assert cover.charge.coat_check is not None and cover.charge.coat_check.amount.cents == 300
    assert cover.viewer_admission is not None and cover.viewer_admission.is_paid
    assert client.venue_cover("gone") is None
    purchase = client.buy_cover("v1", 1500)
    assert purchase.is_square and purchase.admission.claim_check_number == 12
    assert api.last_body is not None and api.last_body["variables"]["amount"] == {"cents": 1500, "currency": "usd"}
    assert client.buy_coat_check("v1", 2).admission.venue_name == "Club"
    assert client.pay_cover("adm-1", "nonce").id == "adm-1"
    assert client.confirm_cover("adm-1").event_name == "Brunch"
    assert client.refund_admission("adm-1").status == "REFUNDED"
    assert len(client.admissions()) == 1
    message = client.send_chat_message("hi", venue_id="v1", prompt_id="p1")
    assert message.body == "hi" and message.sent_at is not None
    assert api.last_body is not None and api.last_body["variables"]["input"] == {
        "venueId": "v1",
        "message": "hi",
        "promptId": "p1",
    }
    client.send_chat_message("hey", locale_id="l1")
    client.remove_chat_message("m1")
    with pytest.raises(ValueError):
        client.send_chat_message("both", venue_id="v", locale_id="l")


async def test_async_rsvp_cover_and_chat(async_client: AsyncClient, api: FakeAPI) -> None:
    member_api(api)
    assert (await async_client.cancel_rsvp("e1")).mine == "UNSURE"
    assert await async_client.venue_cover("v1") is not None
    assert (await async_client.buy_cover("v1")).provider == "SQUARE"
    assert (await async_client.buy_coat_check("v1")).admission.id == "adm-1"
    assert (await async_client.pay_cover("adm-1", "n", "v")).id == "adm-1"
    assert (await async_client.confirm_cover("adm-1")).is_paid
    assert (await async_client.refund_admission("adm-1")).status == "REFUNDED"
    assert len(await async_client.admissions()) == 1
    assert (await async_client.send_chat_message("hi", locale_id="l1")).id == "m1"
    await async_client.remove_chat_message("m1")


def test_cover_pass_codes_match_the_other_sdks() -> None:
    # The same code the Node SDK makes for this pass at this time (and the Swift, Kotlin and PHP SDKs).
    assert cover_pass_code("adm-1", "c2VjcmV0", 1_000_000) == "HMC1.adm-1.33333.ACsUcPO9IVC3ZyQJ"
    assert is_cover_pass_code(cover_pass_code("adm-1", "c2VjcmV0"))
    assert not is_cover_pass_code("HMC1.adm.x.sig") and not is_cover_pass_code("nope")
    assert seconds_until_next_window(1_000_000) == 20


# Calendar, moderation and the account

FEED = {
    "url": "https://api/v1/calendar/s.ics",
    "webcalUrl": "webcal://s",
    "googleUrl": "https://g",
    "venues": [{"id": "v1"}],
}


def account_api(api: FakeAPI, deleted: bool = True) -> None:
    api.operations.update(
        {
            "CalendarFeed": {"data": {"me": {"calendarFeed": None}}},
            "CreateCalendarFeed": {"data": {"createCalendarFeed": {"calendarFeed": FEED}}},
            "SetCalendarFeedVenue": {"data": {"setCalendarFeedVenue": {"calendarFeed": FEED}}},
            "DeleteCalendarFeed": {"data": {"deleteCalendarFeed": {"deleted": True}}},
            "ReportContent": lambda r, b: {
                "data": {"reportContent": {"reported": True, "blocked": True} if b["variables"]["block"] else None}
            },
            "BlockUser": {"data": {"blockUser": {"blockedUsers": []}}},
            "UnblockUser": {"data": {"unblockUser": {"blockedUsers": []}}},
            "DeleteAccount": {"data": {"deleteAccount": {"deleted": deleted}}},
        }
    )


def test_calendar_moderation_and_the_account(client: Client, api: FakeAPI) -> None:
    account_api(api, deleted=False)
    assert client.calendar_feed() is None
    feed = client.create_calendar_feed(reset=True)
    assert feed.webcal_url == "webcal://s" and feed.follows("v1") and not feed.follows("v2")
    assert client.follow_venue_in_calendar("v1").venue_ids == ["v1"]
    assert client.delete_calendar_feed() is True
    result = client.report_content("MESSAGE", "m1", REPORT_REASONS[1], block=True)
    assert result.reported and result.blocked
    assert api.last_body is not None and api.last_body["variables"]["reason"] == "Harassment or hate"
    assert not client.report_content("PERSON", "u1").reported
    client.block_user("u1")
    client.unblock_user("u1")
    assert client.delete_account() is False and client.is_signed_in
    account_api(api, deleted=True)
    assert client.delete_account() is True and not client.is_signed_in


async def test_async_calendar_moderation_and_the_account(async_client: AsyncClient, api: FakeAPI) -> None:
    account_api(api)
    assert await async_client.calendar_feed() is None
    assert (await async_client.create_calendar_feed()).google_url == "https://g"
    assert (await async_client.follow_venue_in_calendar("v1", following=False)).url
    assert await async_client.delete_calendar_feed()
    assert (await async_client.report_content("MESSAGE", "m", block=True)).blocked
    await async_client.block_user("u")
    await async_client.unblock_user("u")
    assert await async_client.delete_account() and not async_client.is_signed_in
