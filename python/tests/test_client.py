from __future__ import annotations

import httpx
import pytest

from audiencekit import (
    API_VERSION,
    AsyncClient,
    AudienceKitError,
    Client,
    Configuration,
    Coordinate,
    Credential,
    DeviceDescription,
    __version__,
)
from audiencekit import errors as codes
from audiencekit.client import _operation_type
from tests.conftest import AUDIENCE_ID, CREDENTIAL_JSON, ENDPOINT, TOKEN, FakeAPI, undefined_field

DEVICE = DeviceDescription("install-1")


def venues_payload() -> dict:
    return {"data": {"venues": {"list": {"nodes": [{"id": "v1", "name": "The Stud", "locale": {"id": "l1"}}]}}}}


# Headers and transport


def test_every_call_carries_the_sdk_headers_and_the_token(client: Client, api: FakeAPI) -> None:
    api.operations["Audience"] = {"data": {"id": AUDIENCE_ID, "name": "Hot Mess", "subdomain": "hotmess"}}
    audience = client.audience()
    assert audience.name == "Hot Mess"
    request = api.last
    assert request.url == httpx.URL(ENDPOINT)
    assert request.headers["Authorization"] == f"Bearer {TOKEN}"
    assert request.headers["X-AudienceKit-API-Version"] == API_VERSION
    assert request.headers["X-AudienceKit-Client"] == f"AudienceKit-Python/{__version__}"
    assert request.headers["X-APOLLO-OPERATION-TYPE"] == "query"
    assert request.headers["X-APOLLO-OPERATION-NAME"] == "Audience"
    assert request.headers["Content-Type"] == "application/json"
    assert "X-AudienceKit-Environment" not in request.headers
    assert api.last_body == {"query": api.last_body["query"], "operationName": "Audience"}


def test_staging_sends_the_environment_header(api: FakeAPI, credential: Credential) -> None:
    client = Client(
        Configuration(environment="staging"), credential=credential, http=httpx.Client(transport=api.transport())
    )
    api.operations["Me"] = {"data": {"me": {"self": {"id": "u1", "name": "Pat"}}}}
    me = client.me()
    assert me is not None and me.name == "Pat"
    assert api.last.headers["X-AudienceKit-Environment"] == "staging"


def test_graphql_goes_to_the_credentials_instance_unless_trusted(api: FakeAPI) -> None:
    next_credential = Credential.from_json(
        {**CREDENTIAL_JSON, "endpoint": f"https://next.audiencekit.com/v1/audience/{AUDIENCE_ID}/graphql"}
    )
    api.operations["Me"] = {"data": {"me": None}}
    client = Client(Configuration(), credential=next_credential, http=httpx.Client(transport=api.transport()))
    assert client.me() is None
    assert api.last.url.host == "next.audiencekit.com"
    trusting = Client(
        Configuration(trusted_credential_origins=("https://next.audiencekit.com",)),
        credential=next_credential,
        http=httpx.Client(transport=api.transport()),
    )
    trusting.me()
    assert api.last.url.host == "api.audiencekit.com"


def test_network_failures_become_network_errors(credential: Credential) -> None:
    def fail(request: httpx.Request) -> httpx.Response:
        raise httpx.ConnectError("no route", request=request)

    client = Client(credential=credential, http=httpx.Client(transport=httpx.MockTransport(fail)))
    with pytest.raises(AudienceKitError) as raised:
        client.me()
    assert raised.value.code == codes.NETWORK
    assert "no route" in raised.value.message


def test_operation_type() -> None:
    assert _operation_type("mutation RSVP { x }") == "mutation"
    assert _operation_type("{ me { id } }") == "query"
    assert _operation_type("subscription S { x }") == "subscription"
    assert _operation_type("") == "query"


def test_context_manager_closes_the_http_client(api: FakeAPI) -> None:
    http = httpx.Client(transport=api.transport())
    with Client(http=http) as client:
        assert not client.is_signed_in
    assert http.is_closed


# GraphQL


def test_graphql_errors_are_raised_even_alongside_data(client: Client, api: FakeAPI) -> None:
    api.operations["RSVPEvent"] = {
        "errors": [{"message": "Not allowed", "extensions": {"code": "FORBIDDEN"}}],
        "data": {"rsvpEvent": None},
    }
    with pytest.raises(AudienceKitError) as raised:
        client.rsvp_event("e1", "ATTENDING")
    assert raised.value.code == codes.FORBIDDEN
    assert api.last.headers["X-APOLLO-OPERATION-TYPE"] == "mutation"
    assert api.last_body["variables"] == {"eventId": "e1", "state": "ATTENDING"}


def test_a_response_without_data_is_a_decoding_error(client: Client, api: FakeAPI) -> None:
    api.operations["Me"] = {"data": None}
    with pytest.raises(AudienceKitError) as raised:
        client.me()
    assert raised.value.code == codes.DECODING
    api.operations["Me"] = httpx.Response(200, content=b"[]")
    with pytest.raises(AudienceKitError) as raised:
        client.me()
    assert raised.value.code == codes.DECODING


def test_a_401_ends_the_session(client: Client, api: FakeAPI) -> None:
    events: list[tuple[str, Credential | None]] = []
    client._listener = lambda event, credential: events.append((event, credential))
    api.operations["Me"] = httpx.Response(401, json={"error": "unauthenticated"})
    with pytest.raises(AudienceKitError) as raised:
        client.me()
    assert raised.value.is_unauthenticated
    assert not client.is_signed_in
    assert events == [("session_ended", None)]
    # Once forgotten, the next call says so without going to the API.
    with pytest.raises(AudienceKitError) as raised:
        client.me()
    assert raised.value.code == codes.NOT_SIGNED_IN
    assert len(api.requests) == 1


def test_other_statuses_map_to_errors(client: Client, api: FakeAPI) -> None:
    api.operations["Me"] = httpx.Response(429, content=b"slow down")
    with pytest.raises(AudienceKitError) as raised:
        client.me()
    assert raised.value.code == codes.RATE_LIMITED and raised.value.status == 429


def test_raw_graphql_with_variables_and_endpoint(client: Client, api: FakeAPI) -> None:
    api.rest[f"POST /v1/audience/{AUDIENCE_ID}/staff"] = httpx.Response(200, json={"data": {"ok": True}})
    data = client.graphql("query X($a: Int) { ok }", {"a": 1}, "X", endpoint="staff")
    assert data == {"ok": True}
    assert api.last_body == {"query": "query X($a: Int) { ok }", "variables": {"a": 1}, "operationName": "X"}


def test_graphql_without_an_audience_is_a_configuration_error(api: FakeAPI) -> None:
    client = Client(Configuration(), http=httpx.Client(transport=api.transport()))
    with pytest.raises(AudienceKitError) as raised:
        client.graphql("{ id }")
    assert raised.value.code == codes.NOT_SIGNED_IN
    client.adopt(Credential.from_json({**CREDENTIAL_JSON, "audienceId": None}))
    with pytest.raises(AudienceKitError) as raised:
        client.graphql("{ id }")
    assert raised.value.code == codes.MISSING_CONFIGURATION


def test_the_audience_is_looked_up_from_branding_once(api: FakeAPI) -> None:
    api.rest["GET /v1/branding"] = httpx.Response(200, json={"audience": {"id": AUDIENCE_ID, "name": "Hot Mess"}})
    api.operations["Venues"] = venues_payload()
    client = Client(Configuration(host="hotmess.social"), http=httpx.Client(transport=api.transport()))
    assert client.audience_id() == AUDIENCE_ID
    assert client.audience_id() == AUDIENCE_ID
    assert api.last.url.params["host"] == "hotmess.social"
    assert "Authorization" not in api.last.headers
    # GraphQL needs a session, as in the Swift and Kotlin SDKs; adopt a service token for server-side use.
    with pytest.raises(AudienceKitError) as raised:
        client.venues()
    assert raised.value.code == codes.NOT_SIGNED_IN
    client.adopt(Credential.from_json({**CREDENTIAL_JSON, "audienceId": None}))
    assert client.venues()[0].name == "The Stud"
    assert [r.url.path for r in api.requests] == ["/v1/branding", f"/v1/audience/{AUDIENCE_ID}/graphql"]


# The undefinedField retry


def test_a_refused_module_field_is_asked_about_once_then_cached(client: Client, api: FakeAPI) -> None:
    attempts: list[str] = []

    def venues(request: httpx.Request, body: dict) -> dict:
        attempts.append(body["query"])
        if "profile" in body["query"] or "places" in body["query"]:
            return undefined_field()
        return venues_payload()

    api.operations["Venues"] = venues
    api.schema = {
        "Venue": ["id", "name", "hidden", "order", "photoUrl", "bannerUrl", "locale", "location", "tags"],
        "Locale": ["id", "name", "label", "cityNames", "bannerUrl"],
        "Location": ["id", "point", "address"],
        "Person": ["id"],
        "Event": ["id"],
    }
    assert client.venues()[0].id == "v1"
    assert api.operation_names() == ["Venues", "SchemaFields", "Venues"]
    assert len(attempts) == 2 and "profile" not in attempts[1]
    client.venues()
    assert api.operation_names() == ["Venues", "SchemaFields", "Venues", "Venues"]
    assert len(attempts) == 3 and "profile" not in attempts[2]


def test_a_type_the_schema_lacks_counts_as_having_no_fields(client: Client, api: FakeAPI) -> None:
    api.operations["Events"] = lambda request, body: (
        undefined_field("tickets", "Event")
        if "tickets" in body["query"]
        else {"data": {"events": {"list": {"nodes": []}}}}
    )
    api.schema = {
        "Event": ["id", "name"],
        "Locale": ["id"],
        "Venue": ["id"],
        "Location": ["id"],
        "Person": ["id"],
        "EventSeries": ["id"],
    }  # no ListingProfile or EventTickets
    assert client.events(locale_id="l1", venue_id="v1", window="PAST", first=5) == []
    shape = client.schema_fields(["EventTickets", "Event"])
    assert not shape.has("EventTickets", "cover") and shape.has("Event", "name")
    assert api.operation_names().count("SchemaFields") == 1
    assert api.bodies[0]["variables"] == {"window": "PAST", "first": 5, "localeId": "l1", "venueId": "v1"}


def test_other_graphql_errors_are_not_retried(client: Client, api: FakeAPI) -> None:
    api.operations["People"] = {"errors": [{"message": "Nope", "extensions": {"code": "FORBIDDEN"}}]}
    with pytest.raises(AudienceKitError):
        client.people()
    assert api.operation_names() == ["People"]


def test_signing_in_again_clears_the_schema_cache(client: Client, api: FakeAPI, credential: Credential) -> None:
    api.schema = {"Venue": ["id"]}
    client.schema_fields(["Venue"])
    client.adopt(credential)
    client.schema_fields(["Venue"])
    assert api.operation_names() == ["SchemaFields", "SchemaFields"]


# Typed calls


def test_typed_calls_decode_their_answers(client: Client, api: FakeAPI) -> None:
    api.operations["People"] = {"data": {"people": {"list": {"nodes": [{"id": "p1", "name": "DJ"}]}}}}
    api.operations["Locales"] = {"data": {"locales": [{"id": "l1", "name": "SF"}]}}
    api.operations["ClosestLocale"] = {"data": {"closestLocale": {"id": "l1", "name": "SF"}}}
    api.operations["Node"] = {"data": {"node": {"__typename": "Venue", "id": "v1"}}}
    api.operations["Event"] = {"data": {"events": {"event": {"id": "e1", "name": "Night"}}}}
    api.operations["EventSeries"] = {"data": {"events": {"series": {"nodes": [{"id": "s1"}]}}}}
    api.operations["Tribes"] = {
        "data": {
            "id": AUDIENCE_ID,
            "tribes": [{"id": "t1", "name": "Bears", "tribe": True}],
            "me": {"self": {"id": "u", "tribes": [{"isPrivate": True, "tag": {"id": "t1", "name": "Bears"}}]}},
        }
    }
    api.operations["IdentifyWithTribe"] = {
        "data": {"identifyWithTribe": {"tribes": [{"isPrivate": False, "tag": {"id": "t2", "name": "Otters"}}]}}
    }
    api.operations["LeaveTribe"] = {"data": {"leaveTribe": {"tribes": []}}}
    api.operations["RSVPEvent"] = {"data": {"rsvpEvent": {"event": {"id": "e1", "rsvp": {"mine": "MAYBE"}}}}}
    api.operations["RegisterDevice"] = {"data": {"registerDevice": {"registered": True}}}

    assert client.people()[0].name == "DJ"
    assert client.locales()[0].name == "SF"
    closest = client.closest_locale(Coordinate(37.7, -122.4), beacon_major=9)
    assert closest is not None and closest.id == "l1"
    assert api.last_body["variables"] == {"near": {"latitude": 37.7, "longitude": -122.4, "beaconMajor": 9}}
    node = client.node("v1")
    assert node is not None and node.typename == "Venue"
    event = client.event("e1")
    assert event is not None and event.name == "Night"
    assert client.event_series(locale_id="l1")[0].id == "s1"
    tribes = client.tribes()
    assert tribes.available[0].tribe is True and tribes.mine[0].is_private
    assert client.identify_with_tribe("t2", is_private=False)[0].tag.name == "Otters"
    assert api.last_body["variables"] == {"tagId": "t2", "isPrivate": False}
    assert client.leave_tribe("t2") == []
    assert client.rsvp_event("e1", "MAYBE") == "MAYBE"
    assert client.register_device("apns-token", app_id="social.hotmess", sandbox=True)
    assert api.last_body["variables"] == {"notificationToken": "apns-token", "appId": "social.hotmess", "sandbox": True}


def test_typed_calls_tolerate_empty_answers(client: Client, api: FakeAPI) -> None:
    api.operations["People"] = {"data": {"people": None}}
    api.operations["Locales"] = {"data": {"locales": None}}
    api.operations["ClosestLocale"] = {"data": {"closestLocale": None}}
    api.operations["Node"] = {"data": {"node": None}}
    api.operations["Event"] = {"data": {"events": None}}
    api.operations["EventSeries"] = {"data": {"events": {}}}
    api.operations["Tribes"] = {"data": {"tribes": None, "me": None}}
    api.operations["RSVPEvent"] = {"data": {"rsvpEvent": {"event": None}}}
    api.operations["RegisterDevice"] = {"data": {"registerDevice": None}}
    api.operations["Me"] = {"data": {"me": {"self": None}}}
    assert client.people() == [] and client.locales() == []
    assert client.closest_locale(Coordinate(0, 0)) is None and client.node("x") is None
    assert client.event("x") is None and client.event_series() == []
    assert client.tribes().available == [] and client.tribes().mine == []
    assert client.rsvp_event("e", "UNSURE") == "UNSURE"
    assert client.register_device("t") is False
    assert client.me() is None


# Sign-in and sign-out


def test_sign_in_with_facebook_stores_the_credential(anonymous: Client, api: FakeAPI) -> None:
    events: list[str] = []
    anonymous._listener = lambda event, credential: events.append(event)
    api.rest["POST /v1/token"] = httpx.Response(200, json=CREDENTIAL_JSON)
    credential = anonymous.sign_in_with_facebook("fb-token", DEVICE)
    assert credential.token == TOKEN and anonymous.credential == credential
    assert events == ["signed_in"]
    assert api.last_body == {
        "device": {"identifier": "install-1", "type": "python"},
        "facebook_token": "fb-token",
        "host": "hotmess.social",
    }
    assert "Authorization" not in api.last.headers


def test_sign_in_variants_send_their_bodies(api: FakeAPI) -> None:
    client = Client(
        Configuration(host="hotmess.social", facebook_app_id="123"), http=httpx.Client(transport=api.transport())
    )
    api.rest["POST /v1/token"] = httpx.Response(200, json=CREDENTIAL_JSON)
    api.rest["POST /v1/token/apple"] = httpx.Response(200, json=CREDENTIAL_JSON)
    client.sign_in_with_facebook_code("code", "https://app/redirect", DEVICE)
    assert api.last_body["code"] == "code" and api.last_body["redirect_uri"] == "https://app/redirect"
    assert api.last_body["facebook_app_id"] == "123"
    client.sign_in_with_apple("apple-jwt", DEVICE, first_name="Pat", last_name="Example")
    assert api.last_body == {
        "identity_token": "apple-jwt",
        "device": DEVICE.to_json(),
        "first_name": "Pat",
        "last_name": "Example",
        "host": "hotmess.social",
    }
    client.connect_facebook("code2", "https://app/redirect", DEVICE)
    assert api.last_body["connect"] is True
    assert api.last.headers["Authorization"] == f"Bearer {TOKEN}"


def test_sign_in_failures(anonymous: Client, api: FakeAPI) -> None:
    api.rest["POST /v1/token"] = httpx.Response(401, json={"error": "unauthorized"})
    with pytest.raises(AudienceKitError) as raised:
        anonymous.sign_in_with_facebook("bad", DEVICE)
    assert raised.value.code == codes.SIGN_IN_REJECTED
    api.rest["POST /v1/token"] = httpx.Response(400, json={"fault": {"message": "No such app"}})
    with pytest.raises(AudienceKitError) as raised:
        anonymous.sign_in_with_facebook("bad", DEVICE)
    assert raised.value.code == codes.SIGN_IN_FAILED and raised.value.message == "No such app"
    api.rest["POST /v1/token"] = httpx.Response(400, json={"error": "unsupported_api_version"})
    with pytest.raises(AudienceKitError) as raised:
        anonymous.sign_in_with_facebook("bad", DEVICE)
    assert raised.value.code == codes.UNSUPPORTED_API_VERSION
    api.rest["POST /v1/token"] = httpx.Response(503, content=b"")
    with pytest.raises(AudienceKitError) as raised:
        anonymous.sign_in_with_facebook("bad", DEVICE)
    assert raised.value.code == codes.INTERNAL
    api.rest["POST /v1/token"] = httpx.Response(200, json={"token": "x"})
    with pytest.raises(AudienceKitError) as raised:
        anonymous.sign_in_with_facebook("bad", DEVICE)
    assert raised.value.code == codes.DECODING
    api.rest["POST /v1/token"] = httpx.Response(200, json=[1])
    with pytest.raises(AudienceKitError) as raised:
        anonymous.sign_in_with_facebook("bad", DEVICE)
    assert raised.value.code == codes.DECODING
    assert not anonymous.is_signed_in


def test_sign_out_forgets_then_revokes(client: Client, api: FakeAPI) -> None:
    api.rest["DELETE /v1/token"] = httpx.Response(204)
    client.sign_out()
    assert not client.is_signed_in
    assert api.last.method == "DELETE" and api.last.headers["Authorization"] == f"Bearer {TOKEN}"
    client.sign_out()  # already signed out: nothing to revoke
    assert len(api.requests) == 1


def test_sign_out_tolerates_a_dead_session_but_reports_other_failures(
    client: Client, api: FakeAPI, credential: Credential
) -> None:
    api.rest["DELETE /v1/token"] = httpx.Response(401)
    client.sign_out()
    client.adopt(credential)
    api.rest["DELETE /v1/token"] = httpx.Response(500, json={"message": "Down"})
    with pytest.raises(AudienceKitError) as raised:
        client.sign_out()
    assert raised.value.code == codes.INTERNAL and raised.value.message == "Down"
    assert not client.is_signed_in


def test_session_rejected_only_for_the_current_token(client: Client, credential: Credential) -> None:
    assert not client.session_rejected("another")
    assert not client.session_rejected(None)
    assert client.session_rejected(credential.token)
    assert not client.is_signed_in
    assert not client.session_rejected(credential.token)


def test_switch_audience_stores_the_new_credential(client: Client, api: FakeAPI) -> None:
    other = {
        **CREDENTIAL_JSON,
        "audienceId": "other",
        "endpoint": "https://api.audiencekit.com/v1/audience/other/graphql",
    }
    api.rest["POST /v1/admin/choices"] = httpx.Response(200, json=other)
    credential = client.switch_audience("other")
    assert credential.audience_id == "other" and client.audience_id() == "other"
    assert api.last_body == {"audience_id": "other"}
    api.rest["POST /v1/admin/choices"] = httpx.Response(200, json=[])
    with pytest.raises(AudienceKitError) as raised:
        client.switch_audience("other")
    assert raised.value.code == codes.DECODING


def test_branding_needs_a_host(api: FakeAPI) -> None:
    client = Client(http=httpx.Client(transport=api.transport()))
    with pytest.raises(AudienceKitError) as raised:
        client.branding()
    assert raised.value.code == codes.MISSING_CONFIGURATION
    with pytest.raises(AudienceKitError) as raised:
        client.audience_id()
    assert raised.value.code == codes.MISSING_CONFIGURATION
    api.rest["GET /v1/branding"] = httpx.Response(200, json={"audience": {"id": "a"}})
    assert client.branding("hotmess.social", app="social.hotmess").audience_id == "a"
    assert api.last.url.params["app"] == "social.hotmess"
    api.rest["GET /v1/branding"] = httpx.Response(200, json=[])
    with pytest.raises(AudienceKitError) as raised:
        client.branding("hotmess.social")
    assert raised.value.code == codes.DECODING


def test_rest_requests_need_a_session_unless_anonymous(anonymous: Client, api: FakeAPI) -> None:
    with pytest.raises(AudienceKitError) as raised:
        anonymous.request("GET", "/v1/me")
    assert raised.value.code == codes.NOT_SIGNED_IN
    api.rest["GET /v1/branding"] = httpx.Response(200, content=b"not json")
    assert anonymous.request("GET", "v1/branding", authenticated=False) is None


# The asyncio client


async def test_async_client_runs_the_same_calls(async_client: AsyncClient, api: FakeAPI) -> None:
    api.operations["Venues"] = lambda request, body: (
        undefined_field() if "profile" in body["query"] else venues_payload()
    )
    api.schema = {"Venue": ["id", "name"], "Locale": ["id"], "Location": ["id"], "Person": ["id"], "Event": ["id"]}
    api.operations["Audience"] = {"data": {"id": AUDIENCE_ID, "name": "Hot Mess", "subdomain": "hotmess"}}
    api.operations["People"] = {"data": {"people": {"list": {"nodes": []}}}}
    api.operations["Locales"] = {"data": {"locales": []}}
    api.operations["ClosestLocale"] = {"data": {"closestLocale": None}}
    api.operations["Me"] = {"data": {"me": {"self": {"id": "u"}}}}
    api.operations["Node"] = {"data": {"node": None}}
    api.operations["Tribes"] = {"data": {"tribes": []}}
    api.operations["IdentifyWithTribe"] = {"data": {"identifyWithTribe": {"tribes": []}}}
    api.operations["LeaveTribe"] = {"data": {"leaveTribe": {"tribes": []}}}
    api.operations["RSVPEvent"] = {"data": {"rsvpEvent": {}}}
    api.operations["RegisterDevice"] = {"data": {"registerDevice": {"registered": True}}}
    api.operations["Events"] = {"data": {"events": {"list": {"nodes": []}}}}
    api.operations["Event"] = {"data": {"events": {"event": None}}}
    api.operations["EventSeries"] = {"data": {"events": {"series": {"nodes": []}}}}
    async with async_client as client:
        assert (await client.venues())[0].name == "The Stud"
        assert (await client.venues())[0].name == "The Stud"
        assert api.operation_names() == ["Venues", "SchemaFields", "Venues", "Venues"]
        assert (await client.audience()).subdomain == "hotmess"
        assert await client.people() == [] and await client.locales() == []
        assert await client.closest_locale(Coordinate(1, 2)) is None
        me = await client.me()
        assert me is not None and me.id == "u"
        assert await client.node("x") is None
        assert (await client.tribes()).mine == []
        assert await client.identify_with_tribe("t") == [] and await client.leave_tribe("t") == []
        assert await client.rsvp_event("e", "DECLINED") == "DECLINED"
        assert await client.register_device("t", app_id="a", sandbox=False)
        assert await client.events() == [] and await client.event("e") is None and await client.event_series() == []
        assert await client.schema_fields(["Venue"]) is not None


async def test_async_sign_in_out_and_errors(api: FakeAPI) -> None:
    client = AsyncClient(Configuration(host="hotmess.social"), http=httpx.AsyncClient(transport=api.async_transport()))
    api.rest["GET /v1/branding"] = httpx.Response(200, json={"audience": {"id": AUDIENCE_ID}})
    assert await client.audience_id() == AUDIENCE_ID
    assert (await client.branding()).audience_id == AUDIENCE_ID
    api.rest["POST /v1/token"] = httpx.Response(200, json=CREDENTIAL_JSON)
    api.rest["POST /v1/token/apple"] = httpx.Response(200, json=CREDENTIAL_JSON)
    assert (await client.sign_in_with_facebook("fb", DEVICE)).token == TOKEN
    assert (await client.sign_in_with_facebook_code("c", "https://r", DEVICE)).token == TOKEN
    assert (await client.sign_in_with_apple("a", DEVICE)).token == TOKEN
    assert (await client.connect_facebook("c", "https://r", DEVICE)).token == TOKEN
    api.rest["POST /v1/admin/choices"] = httpx.Response(200, json=CREDENTIAL_JSON)
    assert (await client.switch_audience(AUDIENCE_ID)).audience_id == AUDIENCE_ID
    api.rest["POST /v1/admin/choices"] = httpx.Response(200, json=[])
    with pytest.raises(AudienceKitError):
        await client.switch_audience(AUDIENCE_ID)
    api.operations["Me"] = httpx.Response(401)
    with pytest.raises(AudienceKitError) as raised:
        await client.me()
    assert raised.value.is_unauthenticated and not client.is_signed_in
    await client.sign_out()
    client.adopt(Credential.from_json(CREDENTIAL_JSON))
    api.rest["DELETE /v1/token"] = httpx.Response(500)
    with pytest.raises(AudienceKitError):
        await client.sign_out()
    client.adopt(Credential.from_json(CREDENTIAL_JSON))
    api.rest["DELETE /v1/token"] = httpx.Response(404)
    await client.sign_out()
    api.operations["People"] = {"errors": [{"message": "Nope", "extensions": {"code": "FORBIDDEN"}}]}
    with pytest.raises(AudienceKitError) as raised:
        await client.people()
    assert raised.value.code == codes.NOT_SIGNED_IN
    client.adopt(Credential.from_json(CREDENTIAL_JSON))
    with pytest.raises(AudienceKitError) as raised:
        await client.people()
    assert raised.value.code == codes.FORBIDDEN
    api.rest["GET /v1/branding"] = httpx.Response(200, json=[])
    bare = AsyncClient(http=httpx.AsyncClient(transport=api.async_transport()))
    with pytest.raises(AudienceKitError):
        await bare.branding()
    with pytest.raises(AudienceKitError):
        await bare.audience_id()
    with pytest.raises(AudienceKitError):
        await client.branding()
    await bare.aclose()
    await client.aclose()


async def test_async_network_failure(credential: Credential) -> None:
    def fail(request: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("slow", request=request)

    client = AsyncClient(credential=credential, http=httpx.AsyncClient(transport=httpx.MockTransport(fail)))
    with pytest.raises(AudienceKitError) as raised:
        await client.me()
    assert raised.value.code == codes.NETWORK
