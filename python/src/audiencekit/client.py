"""The clients: ``Client`` (blocking) and ``AsyncClient`` (asyncio), on httpx.

Both talk to the AudienceKit API on behalf of one audience and one signed-in person. Hand ``sign_in_with_facebook``
a Facebook access token the app obtained (or ``adopt`` a credential minted elsewhere, such as a service token); every
call then carries ``Authorization: Bearer <token>``, the API contract version and the client's name. When the API
rejects the token (HTTP 401) the credential is forgotten and the call raises ``AudienceKitError`` with the
``UNAUTHENTICATED`` code.
"""

from __future__ import annotations

import asyncio
import json
import os
from collections.abc import Awaitable, Callable, Mapping
from typing import Any, TypeVar
from urllib.parse import quote

import httpx

from . import operations as ops
from . import queries
from ._version import __version__
from .config import (
    API_VERSION,
    API_VERSION_HEADER,
    CLIENT_HEADER,
    CONSUMER_ENDPOINT,
    ENVIRONMENT_HEADER,
    Configuration,
    DeviceDescription,
    endpoint_path,
)
from .credential import Credential
from .errors import UNSUPPORTED_API_VERSION_BODY, AudienceKitError, GraphQLError
from .models import (
    JSON,
    RSVP,
    Admission,
    Article,
    ArticlesPage,
    Audience,
    Branding,
    CalendarFeed,
    ChatMessage,
    Community,
    Coordinate,
    CoverPurchase,
    Event,
    EventSeries,
    Locale,
    Node,
    Person,
    Publication,
    PublicListing,
    PublicListingsPage,
    ReportResult,
    SelfUser,
    TribeIdentification,
    Tribes,
    Venue,
    VenueCover,
)
from .operations import Operation
from .schema import EVERYTHING, SchemaShape

T = TypeVar("T")

SERVICE_RENEW_BEFORE_SECONDS = 60
"""How long before a service session expires the client trades its service token again."""

LISTING_PATHS = {"venue": "venues", "event": "events", "post": "posts"}

CredentialListener = Callable[[str, "Credential | None"], None]
"""Told ``("signed_in", credential)``, ``("signed_out", None)`` or ``("session_ended", None)``."""


class _Request:
    """One HTTP request to the API, before httpx sees it."""

    __slots__ = ("authenticated", "body", "headers", "method", "params", "path")

    def __init__(
        self,
        method: str,
        path: str,
        *,
        body: Any = None,
        params: dict[str, str] | None = None,
        authenticated: bool = True,
        headers: dict[str, str] | None = None,
    ) -> None:
        self.method = method
        self.path = path
        self.body = body
        self.params = params or {}
        self.authenticated = authenticated
        self.headers = headers or {}


class _BaseClient:
    """What the blocking and asyncio clients share: the credential, the schema cache and every pure step."""

    def __init__(
        self,
        configuration: Configuration | None = None,
        *,
        credential: Credential | None = None,
        on_session_change: CredentialListener | None = None,
    ) -> None:
        self.configuration = configuration or Configuration()
        self._credential = credential
        self._listener = on_session_change
        self._resolved_audience_id: str | None = None
        self._schema_cache: dict[str, frozenset[str]] = {}
        self._service_token: str | None = None

    @classmethod
    def from_environment(cls: type[_C], environment: Mapping[str, str] | None = None, **options: Any) -> _C:
        """A client configured from the environment, for servers, jobs and scripts: ``AUDIENCEKIT_TOKEN`` (a service
        token, ``akst_…``, traded for sessions as ``use_service_token`` does, or another bearer value such as an
        application API key) and, when set, ``AUDIENCEKIT_BASE_URL``, ``AUDIENCEKIT_HOST``, ``AUDIENCEKIT_AUDIENCE_ID``
        and ``AUDIENCEKIT_ENVIRONMENT``. Reads ``os.environ`` unless given ``environment``; ``options`` go to the
        constructor (``http=…``)."""
        env = os.environ if environment is None else environment

        def read(name: str) -> str | None:
            return env.get(name) or None

        client = cls(
            Configuration(
                base_url=read("AUDIENCEKIT_BASE_URL") or Configuration.base_url,
                host=read("AUDIENCEKIT_HOST"),
                audience_id=read("AUDIENCEKIT_AUDIENCE_ID"),
                environment=read("AUDIENCEKIT_ENVIRONMENT") or "production",
            ),
            **options,
        )
        token = read("AUDIENCEKIT_TOKEN")
        if token and token.startswith("akst_"):
            client._service_token = token
        elif token:
            client.use_bearer_token(token)
        return client

    def use_bearer_token(self, token: str) -> None:
        """Sends ``token`` as is (an application API key, or a session JWT minted elsewhere) as
        ``Authorization: Bearer``, to the configured base URL and audience."""
        self._service_token = None
        self._store(
            Credential(
                token=token,
                user_id=None,
                role="bearer",
                endpoint=self.configuration.base_url.rstrip("/") + "/v1/graphql",
                audience_id=self.configuration.audience_id,
            )
        )

    def _needs_service_trade(self) -> bool:
        """Whether a service token has no session yet, or one about to run out."""
        if self._service_token is None:
            return False
        return self._credential is None or self._credential.expires_within(SERVICE_RENEW_BEFORE_SECONDS)

    def _service_request(self) -> _Request:
        if self._service_token is None:
            raise AudienceKitError.not_signed_in()
        return _Request("POST", "/v1/token/service", body={"service_token": self._service_token}, authenticated=False)

    def _service_result(self, response: httpx.Response) -> Credential:
        if response.status_code in (401, 403):
            self._service_token = None
            raise AudienceKitError.unauthorized("The service token was refused: it is invalid or was revoked.")
        if not 200 <= response.status_code < 300:
            raise AudienceKitError.for_status(response.status_code, self._json(response))
        body = self._json(response)
        if not isinstance(body, dict) or not isinstance(body.get("token"), str):
            raise AudienceKitError.decoding("The service token response had no token.")
        body = {"role": "service", "endpoint": self.configuration.base_url.rstrip("/") + "/v1/graphql", **body}
        credential = Credential.from_json({k: v for k, v in body.items() if v is not None or k == "userId"})
        self._store(credential)
        return credential

    @staticmethod
    def _listing_path(kind: str, id: str) -> str:
        path = LISTING_PATHS.get(kind)
        if path is None:
            raise ValueError(f"A listing is a venue, event or post, not {kind}.")
        return f"/v1/public/{path}/{quote(id, safe='')}"

    # Session state

    @property
    def credential(self) -> Credential | None:
        """The stored credential, or ``None`` before sign-in. Never log its token."""
        return self._credential

    @property
    def is_signed_in(self) -> bool:
        return self._credential is not None

    def adopt(self, credential: Credential) -> None:
        """Makes ``credential`` the session: one minted outside the SDK (a service token, a venue device's), or one
        saved from an earlier run. GraphQL then goes to the API instance its endpoint names, for its audience."""
        self._store(credential)

    def _store(self, credential: Credential) -> None:
        self._credential = credential
        self._schema_cache.clear()
        if self._listener:
            self._listener("signed_in", credential)

    def _forget(self, event: str) -> None:
        if event == "signed_out":
            self._service_token = None
        self._credential = None
        self._schema_cache.clear()
        if self._listener:
            self._listener(event, None)

    def session_rejected(self, token: str | None) -> bool:
        """Ends the session because the API refused ``token`` on a connection the SDK didn't make itself. Does nothing
        (and returns ``False``) when the stored token isn't that one any more."""
        if token is None or self._credential is None or self._credential.token != token:
            return False
        self._forget("session_ended")
        return True

    # Pure request building

    def _headers(self, request: _Request, token: str | None) -> dict[str, str]:
        headers = {
            "Accept": "application/json",
            CLIENT_HEADER: f"AudienceKit-Python/{__version__}",
            API_VERSION_HEADER: API_VERSION,
        }
        if self.configuration.environment != "production":
            headers[ENVIRONMENT_HEADER] = self.configuration.environment
        if request.authenticated and token:
            headers["Authorization"] = f"Bearer {token}"
        if request.body is not None:
            headers["Content-Type"] = "application/json"
        headers.update(request.headers)
        return headers

    def _token_for(self, request: _Request) -> str | None:
        if not request.authenticated:
            return None
        if self._credential is None:
            raise AudienceKitError.not_signed_in()
        return self._credential.token

    def _url(self, request: _Request, base_url: str | None) -> str:
        base = (base_url or self.configuration.base_url).rstrip("/")
        path = request.path if request.path.startswith("/") else "/" + request.path
        return base + path

    def _graphql_request(
        self, query: str, variables: JSON | None, operation_name: str | None, endpoint: str
    ) -> tuple[_Request, str | None]:
        """The request for an operation and the API instance to send it to (the credential's, or the base URL)."""
        audience_id = self._known_audience_id()
        if audience_id is None:
            raise AudienceKitError.missing_configuration("set an audience_id or a host")
        body: JSON = {"query": query}
        if variables is not None:
            body["variables"] = variables
        if operation_name is not None:
            body["operationName"] = operation_name
        headers = {"X-APOLLO-OPERATION-TYPE": _operation_type(query)}
        if operation_name:
            headers["X-APOLLO-OPERATION-NAME"] = operation_name
        request = _Request("POST", endpoint_path(audience_id, endpoint), body=body, headers=headers)
        base = self.configuration.api_base(self._credential.endpoint if self._credential else None)
        return request, base

    def _known_audience_id(self) -> str | None:
        """The audience without asking the API: the credential's, the configured one, or the one branding found."""
        if self._credential is not None and self._credential.audience_id:
            return self._credential.audience_id
        return self.configuration.audience_id or self._resolved_audience_id

    # Pure response handling

    @staticmethod
    def _json(response: httpx.Response) -> Any:
        if not response.content:
            return None
        try:
            return response.json()
        except ValueError:
            return None

    def _rest_result(self, response: httpx.Response, token: str | None) -> Any:
        """The body of a successful REST response, or the error for its status; a 401 on an authenticated request
        ends the session."""
        if 200 <= response.status_code < 300:
            return self._json(response)
        if response.status_code == 401 and token is not None:
            self.session_rejected(token)
            raise AudienceKitError.unauthorized()
        raise AudienceKitError.for_status(response.status_code, self._json(response))

    def _sign_in_result(self, response: httpx.Response) -> Credential:
        body = self._json(response)
        if 200 <= response.status_code < 300:
            if not isinstance(body, dict):
                raise AudienceKitError.decoding("The sign-in response wasn't an object.")
            try:
                credential = Credential.from_json(body)
            except (KeyError, TypeError) as error:
                raise AudienceKitError.decoding(f"The sign-in response is missing {error}.") from error
            self._store(credential)
            return credential
        if response.status_code == 401:
            raise AudienceKitError.sign_in_rejected()
        if response.status_code == 400 and not (
            isinstance(body, dict) and body.get("error") == UNSUPPORTED_API_VERSION_BODY
        ):
            fault = body.get("fault") if isinstance(body, dict) and isinstance(body.get("fault"), dict) else {}
            message = (body.get("message") if isinstance(body, dict) else None) or (fault or {}).get("message")
            raise AudienceKitError.sign_in_failed(message if isinstance(message, str) else None)
        raise AudienceKitError.for_status(response.status_code, body)

    @staticmethod
    def _graphql_result(body: Any) -> JSON:
        """An operation's ``data``: errors first, because a refused mutation comes back as
        ``{"errors": […], "data": {"field": null}}`` and decoding the data would hide the refusal."""
        if not isinstance(body, dict):
            raise AudienceKitError.decoding("The response wasn't a GraphQL envelope.")
        errors = body.get("errors")
        if isinstance(errors, list) and errors:
            raise AudienceKitError.graphql([GraphQLError.from_json(e) for e in errors if isinstance(e, dict)])
        data = body.get("data")
        if not isinstance(data, dict):
            raise AudienceKitError.decoding("The response had no data.")
        return data

    def _cached_shape(self, types: list[str], endpoint: str) -> SchemaShape | None:
        """The schema shape for ``types`` when the session already knows every one of them."""
        audience_id = self._known_audience_id()
        if audience_id is None:
            return None
        prefix = f"{audience_id}|{endpoint}|"
        if any(prefix + name not in self._schema_cache for name in types):
            return None
        return SchemaShape(
            {name: self._schema_cache[prefix + name] for name in types if self._schema_cache[prefix + name]}
        )

    def _remember_schema(self, types: list[str], endpoint: str, data: JSON) -> SchemaShape:
        prefix = f"{self._known_audience_id()}|{endpoint}|"
        for index, name in enumerate(types):
            found = data.get(f"t{index}")
            fields = found.get("fields") if isinstance(found, dict) else None
            names = set()
            if isinstance(fields, list):
                names = {f["name"] for f in fields if isinstance(f, dict) and "name" in f}
            self._schema_cache[prefix + name] = frozenset(names)
        shape = self._cached_shape(types, endpoint)
        assert shape is not None  # every type was just cached
        return shape

    def _missing_types(self, types: list[str], endpoint: str) -> list[str]:
        prefix = f"{self._known_audience_id()}|{endpoint}|"
        return sorted({name for name in types if prefix + name not in self._schema_cache})


_C = TypeVar("_C", bound="_BaseClient")


def _community(parts: list[Any]) -> Community:
    audience, locales, venues, people, events, series = parts
    return Community(
        audience=audience,
        locales=locales or [],
        venues=venues or [],
        people=people or [],
        events=events or [],
        event_series=series or [],
    )


def _operation_type(query: str) -> str:
    """``query``, ``mutation`` or ``subscription``: the document's first keyword."""
    for token in query.replace("{", " { ").split():
        if token in ("query", "mutation", "subscription"):
            return token
        if token == "{":
            break
    return "query"


def _network_error(error: httpx.HTTPError) -> AudienceKitError:
    return AudienceKitError.network(str(error) or error.__class__.__name__)


class Client(_BaseClient):
    """A blocking client. Use it as a context manager, or ``close()`` it, to release its connections.

    ``http`` is the ``httpx.Client`` to send with; the default follows ``configuration.base_url``. Pass your own to set
    timeouts, proxies, or a ``MockTransport`` in tests.
    """

    def __init__(
        self,
        configuration: Configuration | None = None,
        *,
        credential: Credential | None = None,
        http: httpx.Client | None = None,
        on_session_change: CredentialListener | None = None,
    ) -> None:
        super().__init__(configuration, credential=credential, on_session_change=on_session_change)
        self._http = http or httpx.Client(timeout=30.0)

    def __enter__(self) -> Client:
        return self

    def __exit__(self, *exc: object) -> None:
        self.close()

    def close(self) -> None:
        self._http.close()

    # Transport

    def _send(self, request: _Request, *, token: str | None = None, base_url: str | None = None) -> httpx.Response:
        headers = self._headers(request, token)
        content = json.dumps(request.body).encode() if request.body is not None else None
        try:
            return self._http.request(
                request.method,
                self._url(request, base_url),
                params=request.params or None,
                headers=headers,
                content=content,
            )
        except httpx.HTTPError as error:
            raise _network_error(error) from error

    def request(
        self,
        method: str,
        path: str,
        *,
        body: Any = None,
        params: dict[str, str] | None = None,
        authenticated: bool = True,
    ) -> Any:
        """Sends a request to a REST endpoint and returns the JSON body of a successful response."""
        request = _Request(method, path, body=body, params=params, authenticated=authenticated)
        response, token = self._send_with_session(request)
        return self._rest_result(response, token)

    def _ensure_session(self) -> None:
        """Trades the service token when there's no session yet, or it is about to run out."""
        if self._needs_service_trade():
            self._trade_service_token()

    def _trade_service_token(self) -> Credential:
        return self._service_result(self._send(self._service_request()))

    def _send_with_session(self, request: _Request, base_url: str | None = None) -> tuple[httpx.Response, str | None]:
        """Sends ``request`` with the session, trading the service token first when needed and once more when the
        API refuses its session (after a key rotation, say)."""
        if request.authenticated:
            self._ensure_session()
        token = self._token_for(request)
        response = self._send(request, token=token, base_url=base_url)
        if response.status_code == 401 and token is not None and self._service_token is not None:
            token = self._trade_service_token().token
            response = self._send(request, token=token, base_url=base_url)
        return response, token

    # Session

    def use_service_token(self, service_token: str) -> Credential:
        """Acts for the audience with a service token an admin minted in its console (``akst_<prefix>_<secret>``): a
        server or agent rather than a person. Trades it at ``POST /v1/token/service`` for an hour-long session now,
        again a minute before that runs out, and once more when the API refuses it. A token with ``public:read``
        reads the public listings. A revoked token raises ``UNAUTHENTICATED``."""
        self._service_token = service_token
        return self._trade_service_token()

    def sign_in_with_facebook(self, access_token: str, device: DeviceDescription) -> Credential:
        """Exchanges a Facebook user access token for an AudienceKit session and stores it. Sends the configured host
        and Facebook app ID so the API checks the token against the right app and binds the session to the audience."""
        return self._sign_in("/v1/token", _facebook_body(self.configuration, device, facebook_token=access_token))

    def sign_in_with_facebook_code(self, code: str, redirect_uri: str, device: DeviceDescription) -> Credential:
        """Exchanges the code from Facebook's OAuth dialog (Facebook Login for Business) for a session."""
        return self._sign_in(
            "/v1/token", _facebook_body(self.configuration, device, code=code, redirect_uri=redirect_uri)
        )

    def sign_in_with_apple(
        self,
        identity_token: str,
        device: DeviceDescription,
        *,
        first_name: str | None = None,
        last_name: str | None = None,
        authorization_code: str | None = None,
        redirect_uri: str | None = None,
        nonce: str | None = None,
    ) -> Credential:
        """Exchanges a Sign in with Apple identity token for a session. Apple gives the person's name only the first
        time; pass it then. Sign in with Apple JS also gives an authorization code; pass it with the redirect URI and
        nonce the sign-in was opened with."""
        body = _apple_body(self.configuration, device, identity_token, first_name, last_name)
        body.update(_present(authorization_code=authorization_code, redirect_uri=redirect_uri, nonce=nonce))
        return self._sign_in("/v1/token/apple", body)

    def sign_in_with_google(
        self, id_token: str, device: DeviceDescription, *, name: str | None = None, access_token: str | None = None
    ) -> Credential:
        """Exchanges a Google ID token for a session. Pass ``access_token`` (an OAuth token for
        ``https://www.googleapis.com/auth/user.emails.read``) and the API can also match an existing account by the
        Google account's other verified emails."""
        return self._sign_in("/v1/token/google", _google_body(self.configuration, device, id_token, name, access_token))

    def connect_google(self, id_token: str, device: DeviceDescription) -> Credential:
        """Connects a Google account to the signed-in account and stores the new session."""
        body = _google_body(self.configuration, device, id_token, None, None)
        body["connect"] = True
        return self._sign_in("/v1/token/google", body, authenticated=True)

    def sign_in_with_review_code(self, code: str, device: DeviceDescription) -> Credential:
        """Signs an App Reviewer in with the code the audience's console issued, while it is in App Review."""
        return self._sign_in("/v1/token/review", _review_body(self.configuration, device, code))

    def refresh_session(self) -> Credential:
        """Re-issues the token for the same session (``POST /v1/token/refresh``) and stores it."""
        body = self.request("POST", "/v1/token/refresh")
        if not isinstance(body, dict):
            raise AudienceKitError.decoding("The response wasn't a credential.")
        credential = Credential.from_json(body)
        self._store(credential)
        return credential

    def connect_facebook(self, code: str, redirect_uri: str, device: DeviceDescription) -> Credential:
        """Connects Facebook to the signed-in account (one that signed in with Apple) and stores the new session."""
        body = _facebook_body(self.configuration, device, code=code, redirect_uri=redirect_uri)
        body["connect"] = True
        return self._sign_in("/v1/token", body, authenticated=True)

    def _sign_in(self, path: str, body: JSON, authenticated: bool = False) -> Credential:
        request = _Request("POST", path, body=body, authenticated=authenticated)
        token = self._token_for(request)
        return self._sign_in_result(self._send(request, token=token))

    def switch_audience(self, audience_id: str) -> Credential:
        """Moves a platform-console session to another audience and stores the credential the API returns."""
        body = self.request("POST", "/v1/admin/choices", body={"audience_id": audience_id})
        if not isinstance(body, dict):
            raise AudienceKitError.decoding("The response wasn't a credential.")
        credential = Credential.from_json(body)
        self._store(credential)
        return credential

    def sign_out(self) -> None:
        """Ends the session: forgets the credential, then revokes the token with ``DELETE /v1/token``. A 401 or 404
        (the session was already gone) is not an error; any other failure is raised after the device is signed out."""
        credential = self._credential
        self._forget("signed_out")
        if credential is None:
            return
        response = self._send(_Request("DELETE", "/v1/token"), token=credential.token)
        if 200 <= response.status_code < 300 or response.status_code in (401, 404):
            return
        raise AudienceKitError.for_status(response.status_code, self._json(response))

    # Branding and audience

    def branding(self, host: str | None = None, app: str | None = None) -> Branding:
        """The audience's public branding for ``host`` (the configured one by default). No sign-in needed."""
        host = host or self.configuration.host
        if not host:
            raise AudienceKitError.missing_configuration("branding needs a host")
        params = {"host": host}
        if app:
            params["app"] = app
        body = self.request("GET", "/v1/branding", params=params, authenticated=False)
        if not isinstance(body, dict):
            raise AudienceKitError.decoding("The branding response wasn't an object.")
        return Branding.from_json(body)

    def audience_id(self) -> str:
        """The audience this client queries: the credential's, else the configured ID, else the one that owns the
        configured host (looked up once)."""
        known = self._known_audience_id()
        if known is not None:
            return known
        if not self.configuration.host:
            raise AudienceKitError.missing_configuration("set an audience_id or a host")
        self._resolved_audience_id = self.branding().audience_id
        return self._resolved_audience_id

    # GraphQL

    def graphql(
        self,
        query: str,
        variables: JSON | None = None,
        operation_name: str | None = None,
        endpoint: str = CONSUMER_ENDPOINT,
    ) -> JSON:
        """Runs an operation against the audience's endpoint and returns its ``data``. Raises ``AudienceKitError``
        when the response carries errors, even alongside data."""
        self._ensure_session()
        if self._credential is None:
            raise AudienceKitError.not_signed_in()
        self.audience_id()
        request, base = self._graphql_request(query, variables, operation_name, endpoint)
        response, token = self._send_with_session(request, base)
        return self._graphql_result(self._rest_result(response, token))

    def schema_fields(self, types: list[str], endpoint: str = CONSUMER_ENDPOINT) -> SchemaShape:
        """Which fields each of ``types`` has in the audience's schema, cached for the session."""
        missing = self._missing_types(types, endpoint)
        if missing:
            data = self.graphql(queries.schema_fields(missing), operation_name="SchemaFields", endpoint=endpoint)
            self._remember_schema(missing, endpoint, data)
        return self._cached_shape(types, endpoint) or SchemaShape({})

    def run(self, operation: Operation[T], endpoint: str = CONSUMER_ENDPOINT) -> T:
        """Runs a typed operation: first for an audience with every module; when the API refuses a field
        (``undefinedField``), asks the schema which fields its types have and runs it again with only those."""
        self._ensure_session()
        if self._credential is None:
            raise AudienceKitError.not_signed_in()

        def attempt(shape: SchemaShape) -> T:
            data = self.graphql(operation.text(shape), operation.variables, operation.name, endpoint)
            return operation.decode(data)

        if not operation.types:
            return attempt(EVERYTHING)
        known = self._cached_shape(operation.types, endpoint)
        if known is not None:
            return attempt(known)
        try:
            return attempt(EVERYTHING)
        except AudienceKitError as error:
            if not error.is_undefined_field:
                raise
        return attempt(self.schema_fields(operation.types, endpoint))

    # Typed calls

    def audience(self) -> Audience:
        return self.run(ops.audience())

    def venues(self) -> list[Venue]:
        return self.run(ops.venues())

    def people(self) -> list[Person]:
        return self.run(ops.people())

    def locales(self) -> list[Locale]:
        return self.run(ops.locales())

    def closest_locale(self, position: Coordinate, beacon_major: int | None = None) -> Locale | None:
        return self.run(ops.closest_locale(position, beacon_major))

    def me(self) -> SelfUser | None:
        return self.run(ops.me())

    def node(self, id: str) -> Node | None:
        return self.run(ops.node(id))

    def tribes(self) -> Tribes:
        return self.run(ops.tribes())

    def identify_with_tribe(self, tag_id: str, is_private: bool | None = None) -> list[TribeIdentification]:
        return self.run(ops.identify_with_tribe(tag_id, is_private))

    def leave_tribe(self, tag_id: str) -> list[TribeIdentification]:
        return self.run(ops.leave_tribe(tag_id))

    def rsvp_event(self, event_id: str, state: str) -> str:
        """Answers an event's RSVP (``ATTENDING``, ``MAYBE``, ``DECLINED`` or ``UNSURE``) and returns the answer."""
        return self.run(ops.rsvp_event(event_id, state))

    def register_device(self, notification_token: str, app_id: str | None = None, sandbox: bool | None = None) -> bool:
        return self.run(ops.register_device(notification_token, app_id, sandbox))

    def events(
        self, window: str = "UPCOMING", locale_id: str | None = None, venue_id: str | None = None, first: int = 100
    ) -> list[Event]:
        """The audience's events, soonest first for ``UPCOMING`` (latest first for ``PAST``)."""
        return self.run(ops.events(window, locale_id, venue_id, first))

    def event(self, id: str) -> Event | None:
        return self.run(ops.event(id))

    def event_series(
        self, locale_id: str | None = None, venue_id: str | None = None, first: int = 100
    ) -> list[EventSeries]:
        return self.run(ops.event_series(locale_id, venue_id, first))

    def cancel_rsvp(self, event_id: str) -> RSVP:
        """Takes back the signed-in person's RSVP, as if they'd never answered."""
        return self.run(ops.cancel_rsvp(event_id))

    def community(self) -> Community:
        """Everything the audience lists in one go: the audience, its locales, venues, people, upcoming events and
        event series. A part whose module the audience doesn't have comes back empty."""
        reads: list[Callable[[], Any]] = [
            self.audience,
            self.locales,
            self.venues,
            self.people,
            self.events,
            self.event_series,
        ]
        parts: list[Any] = []
        for read in reads:
            try:
                parts.append(read())
            except AudienceKitError as error:
                if not error.is_undefined_field:
                    raise
                parts.append(None)
        return _community(parts)

    # Cover and chat

    def venue_cover(self, venue_id: str) -> VenueCover | None:
        return self.run(ops.venue_cover(venue_id))

    def buy_cover(self, venue_id: str, amount_cents: int | None = None, currency: str = "usd") -> CoverPurchase:
        """Starts paying tonight's cover at a venue: finish with Stripe and ``confirm_cover``, or with a Square
        payment token and ``pay_cover``. ``amount_cents`` is the buyer's choice on a sliding scale."""
        return self.run(ops.buy_cover(venue_id, amount_cents, currency))

    def buy_coat_check(self, venue_id: str, quantity: int = 1) -> CoverPurchase:
        return self.run(ops.buy_coat_check(venue_id, quantity))

    def pay_cover(self, admission_id: str, source_id: str, verification_token: str | None = None) -> Admission:
        return self.run(ops.pay_cover(admission_id, source_id, verification_token))

    def confirm_cover(self, admission_id: str) -> Admission:
        return self.run(ops.confirm_cover(admission_id))

    def refund_admission(self, admission_id: str) -> Admission:
        return self.run(ops.refund_admission(admission_id))

    def admissions(self) -> list[Admission]:
        return self.run(ops.admissions())

    def send_chat_message(
        self, text: str, *, venue_id: str | None = None, locale_id: str | None = None, prompt_id: str | None = None
    ) -> ChatMessage:
        return self.run(ops.send_chat_message(text, venue_id, locale_id, prompt_id))

    def remove_chat_message(self, message_id: str) -> None:
        self.run(ops.remove_chat_message(message_id))

    # Soapbox (news)

    def articles(
        self, locale_id: str | None = None, publication_id: str | None = None, first: int | None = None
    ) -> list[Article]:
        """The audience's live articles, pinned first, then newest. Empty without Soapbox."""
        return self.run(ops.articles(locale_id, publication_id, first))

    def articles_page(
        self, locale_id: str | None = None, publication_id: str | None = None, first: int = 20, after: str | None = None
    ) -> ArticlesPage:
        return self.run(ops.articles_page(locale_id, publication_id, first, after))

    def national_articles(self, locale_id: str | None = None, first: int | None = None) -> list[Article]:
        return self.run(ops.national_articles(locale_id, first))

    def article(self, id: str) -> Article | None:
        return self.run(ops.article(id))

    def articles_about(self, topic: str, id: str, first: int | None = None) -> list[Article]:
        """Live articles about a ``venue``, ``event``, ``person`` or ``locale``: "In the news" on its page."""
        return self.run(ops.articles_about(topic, id, first))

    def publications(self) -> list[Publication]:
        return self.run(ops.publications())

    def local_publications(self, locale_id: str) -> list[Publication]:
        """The publications covering a locale: the "local publishers" at the top of its news."""
        return [p for p in self.publications() if p.locale and p.locale.id.lower() == locale_id.lower()]

    def publication(self, id: str) -> Publication | None:
        return self.run(ops.publication(id))

    def my_op_eds(self) -> list[Article]:
        return self.run(ops.my_op_eds())

    def submit_op_ed(
        self, publication_id: str, title: str, body: str, *, summary: str | None = None, byline: str | None = None
    ) -> Article:
        return self.run(ops.submit_op_ed(publication_id, title, body, summary, byline))

    # Calendar subscription

    def calendar_feed(self) -> CalendarFeed | None:
        return self.run(ops.calendar_feed())

    def create_calendar_feed(self, reset: bool = False) -> CalendarFeed:
        """Their calendar subscription, made on first ask; ``reset`` gives it a new link."""
        return self.run(ops.create_calendar_feed(reset))

    def follow_venue_in_calendar(self, venue_id: str, following: bool = True) -> CalendarFeed:
        return self.run(ops.follow_venue_in_calendar(venue_id, following))

    def delete_calendar_feed(self) -> bool:
        return self.run(ops.delete_calendar_feed())

    # Moderation and the account

    def report_content(self, target_type: str, id: str, reason: str | None = None, block: bool = False) -> ReportResult:
        """Files a report with the audience's admins; with ``block``, blocks the person behind it. Offer
        ``REPORT_REASONS`` as the reasons."""
        return self.run(ops.report_content(target_type, id, reason, block))

    def block_user(self, user_id: str) -> None:
        self.run(ops.block_user(user_id))

    def unblock_user(self, user_id: str) -> None:
        self.run(ops.unblock_user(user_id))

    def delete_account(self) -> bool:
        """Deletes the signed-in person's account for good and forgets the session. It can't be undone: ask first.
        Returns whether the account is gone; when it isn't, the person stays signed in."""
        deleted = self.run(ops.delete_account())
        if deleted:
            self._forget("signed_out")
        return deleted

    # Public listings (REST)

    def public_listings_page(self, page: int = 1) -> PublicListingsPage:
        """One page (from 1) of the audience's public listings: up to 500 venues, then events, then posts. Needs a
        service token with ``public:read``."""
        return PublicListingsPage.from_json(
            self.request("GET", "/v1/public/listings", params={"page": str(max(1, page))})
        )

    def public_listings(self) -> list[PublicListing]:
        """Every public listing, page by page."""
        listings: list[PublicListing] = []
        page = 1
        while True:
            found = self.public_listings_page(page)
            listings.extend(found.listings)
            if found.next_page is None or found.next_page <= page:
                return listings
            page = found.next_page

    def public_listing(self, kind: str, id: str) -> PublicListing | None:
        """One public listing (``venue``, ``event`` or ``post``), or ``None`` when it's gone."""
        try:
            body = self.request("GET", self._listing_path(kind, id))
        except AudienceKitError as error:
            if error.code == "NOT_FOUND":
                return None
            raise
        return PublicListing.from_json(body) if isinstance(body, dict) else None

    def public_tonight(self, venue_id: str) -> JSON:
        """Tonight at a venue, as a screen facing the room shows it: tonight's event, who's on and what's next."""
        body = self.request("GET", f"/v1/public/venues/{quote(venue_id, safe='')}/tonight")
        return body if isinstance(body, dict) else {}


class AsyncClient(_BaseClient):
    """The same client for asyncio. Use it as an async context manager, or ``aclose()`` it."""

    def __init__(
        self,
        configuration: Configuration | None = None,
        *,
        credential: Credential | None = None,
        http: httpx.AsyncClient | None = None,
        on_session_change: CredentialListener | None = None,
    ) -> None:
        super().__init__(configuration, credential=credential, on_session_change=on_session_change)
        self._http = http or httpx.AsyncClient(timeout=30.0)
        self._trade: asyncio.Future[Credential] | None = None

    async def __aenter__(self) -> AsyncClient:
        return self

    async def __aexit__(self, *exc: object) -> None:
        await self.aclose()

    async def aclose(self) -> None:
        await self._http.aclose()

    async def _send(
        self, request: _Request, *, token: str | None = None, base_url: str | None = None
    ) -> httpx.Response:
        headers = self._headers(request, token)
        content = json.dumps(request.body).encode() if request.body is not None else None
        try:
            return await self._http.request(
                request.method,
                self._url(request, base_url),
                params=request.params or None,
                headers=headers,
                content=content,
            )
        except httpx.HTTPError as error:
            raise _network_error(error) from error

    async def request(
        self,
        method: str,
        path: str,
        *,
        body: Any = None,
        params: dict[str, str] | None = None,
        authenticated: bool = True,
    ) -> Any:
        request = _Request(method, path, body=body, params=params, authenticated=authenticated)
        response, token = await self._send_with_session(request)
        return self._rest_result(response, token)

    async def _ensure_session(self) -> None:
        if self._needs_service_trade():
            await self._trade_service_token()

    async def _trade_service_token(self) -> Credential:
        # One trade at a time, however many calls are waiting for it.
        if self._trade is None:
            self._trade = asyncio.ensure_future(self._perform_trade())
        try:
            return await asyncio.shield(self._trade)
        finally:
            if self._trade is not None and self._trade.done():
                self._trade = None

    async def _perform_trade(self) -> Credential:
        return self._service_result(await self._send(self._service_request()))

    async def _send_with_session(
        self, request: _Request, base_url: str | None = None
    ) -> tuple[httpx.Response, str | None]:
        if request.authenticated:
            await self._ensure_session()
        token = self._token_for(request)
        response = await self._send(request, token=token, base_url=base_url)
        if response.status_code == 401 and token is not None and self._service_token is not None:
            token = (await self._trade_service_token()).token
            response = await self._send(request, token=token, base_url=base_url)
        return response, token

    async def use_service_token(self, service_token: str) -> Credential:
        """Acts for the audience with a service token; see ``Client.use_service_token``."""
        self._service_token = service_token
        return await self._trade_service_token()

    async def sign_in_with_facebook(self, access_token: str, device: DeviceDescription) -> Credential:
        return await self._sign_in("/v1/token", _facebook_body(self.configuration, device, facebook_token=access_token))

    async def sign_in_with_facebook_code(self, code: str, redirect_uri: str, device: DeviceDescription) -> Credential:
        return await self._sign_in(
            "/v1/token", _facebook_body(self.configuration, device, code=code, redirect_uri=redirect_uri)
        )

    async def sign_in_with_apple(
        self,
        identity_token: str,
        device: DeviceDescription,
        *,
        first_name: str | None = None,
        last_name: str | None = None,
        authorization_code: str | None = None,
        redirect_uri: str | None = None,
        nonce: str | None = None,
    ) -> Credential:
        body = _apple_body(self.configuration, device, identity_token, first_name, last_name)
        body.update(_present(authorization_code=authorization_code, redirect_uri=redirect_uri, nonce=nonce))
        return await self._sign_in("/v1/token/apple", body)

    async def sign_in_with_google(
        self, id_token: str, device: DeviceDescription, *, name: str | None = None, access_token: str | None = None
    ) -> Credential:
        return await self._sign_in(
            "/v1/token/google", _google_body(self.configuration, device, id_token, name, access_token)
        )

    async def connect_google(self, id_token: str, device: DeviceDescription) -> Credential:
        body = _google_body(self.configuration, device, id_token, None, None)
        body["connect"] = True
        return await self._sign_in("/v1/token/google", body, authenticated=True)

    async def sign_in_with_review_code(self, code: str, device: DeviceDescription) -> Credential:
        return await self._sign_in("/v1/token/review", _review_body(self.configuration, device, code))

    async def refresh_session(self) -> Credential:
        body = await self.request("POST", "/v1/token/refresh")
        if not isinstance(body, dict):
            raise AudienceKitError.decoding("The response wasn't a credential.")
        credential = Credential.from_json(body)
        self._store(credential)
        return credential

    async def connect_facebook(self, code: str, redirect_uri: str, device: DeviceDescription) -> Credential:
        body = _facebook_body(self.configuration, device, code=code, redirect_uri=redirect_uri)
        body["connect"] = True
        return await self._sign_in("/v1/token", body, authenticated=True)

    async def _sign_in(self, path: str, body: JSON, authenticated: bool = False) -> Credential:
        request = _Request("POST", path, body=body, authenticated=authenticated)
        token = self._token_for(request)
        return self._sign_in_result(await self._send(request, token=token))

    async def switch_audience(self, audience_id: str) -> Credential:
        body = await self.request("POST", "/v1/admin/choices", body={"audience_id": audience_id})
        if not isinstance(body, dict):
            raise AudienceKitError.decoding("The response wasn't a credential.")
        credential = Credential.from_json(body)
        self._store(credential)
        return credential

    async def sign_out(self) -> None:
        credential = self._credential
        self._forget("signed_out")
        if credential is None:
            return
        response = await self._send(_Request("DELETE", "/v1/token"), token=credential.token)
        if 200 <= response.status_code < 300 or response.status_code in (401, 404):
            return
        raise AudienceKitError.for_status(response.status_code, self._json(response))

    async def branding(self, host: str | None = None, app: str | None = None) -> Branding:
        host = host or self.configuration.host
        if not host:
            raise AudienceKitError.missing_configuration("branding needs a host")
        params = {"host": host}
        if app:
            params["app"] = app
        body = await self.request("GET", "/v1/branding", params=params, authenticated=False)
        if not isinstance(body, dict):
            raise AudienceKitError.decoding("The branding response wasn't an object.")
        return Branding.from_json(body)

    async def audience_id(self) -> str:
        known = self._known_audience_id()
        if known is not None:
            return known
        if not self.configuration.host:
            raise AudienceKitError.missing_configuration("set an audience_id or a host")
        self._resolved_audience_id = (await self.branding()).audience_id
        return self._resolved_audience_id

    async def graphql(
        self,
        query: str,
        variables: JSON | None = None,
        operation_name: str | None = None,
        endpoint: str = CONSUMER_ENDPOINT,
    ) -> JSON:
        await self._ensure_session()
        if self._credential is None:
            raise AudienceKitError.not_signed_in()
        await self.audience_id()
        request, base = self._graphql_request(query, variables, operation_name, endpoint)
        response, token = await self._send_with_session(request, base)
        return self._graphql_result(self._rest_result(response, token))

    async def schema_fields(self, types: list[str], endpoint: str = CONSUMER_ENDPOINT) -> SchemaShape:
        missing = self._missing_types(types, endpoint)
        if missing:
            data = await self.graphql(queries.schema_fields(missing), operation_name="SchemaFields", endpoint=endpoint)
            self._remember_schema(missing, endpoint, data)
        return self._cached_shape(types, endpoint) or SchemaShape({})

    async def run(self, operation: Operation[T], endpoint: str = CONSUMER_ENDPOINT) -> T:
        await self._ensure_session()
        if self._credential is None:
            raise AudienceKitError.not_signed_in()

        async def attempt(shape: SchemaShape) -> T:
            data = await self.graphql(operation.text(shape), operation.variables, operation.name, endpoint)
            return operation.decode(data)

        if not operation.types:
            return await attempt(EVERYTHING)
        known = self._cached_shape(operation.types, endpoint)
        if known is not None:
            return await attempt(known)
        try:
            return await attempt(EVERYTHING)
        except AudienceKitError as error:
            if not error.is_undefined_field:
                raise
        return await attempt(await self.schema_fields(operation.types, endpoint))

    async def audience(self) -> Audience:
        return await self.run(ops.audience())

    async def venues(self) -> list[Venue]:
        return await self.run(ops.venues())

    async def people(self) -> list[Person]:
        return await self.run(ops.people())

    async def locales(self) -> list[Locale]:
        return await self.run(ops.locales())

    async def closest_locale(self, position: Coordinate, beacon_major: int | None = None) -> Locale | None:
        return await self.run(ops.closest_locale(position, beacon_major))

    async def me(self) -> SelfUser | None:
        return await self.run(ops.me())

    async def node(self, id: str) -> Node | None:
        return await self.run(ops.node(id))

    async def tribes(self) -> Tribes:
        return await self.run(ops.tribes())

    async def identify_with_tribe(self, tag_id: str, is_private: bool | None = None) -> list[TribeIdentification]:
        return await self.run(ops.identify_with_tribe(tag_id, is_private))

    async def leave_tribe(self, tag_id: str) -> list[TribeIdentification]:
        return await self.run(ops.leave_tribe(tag_id))

    async def rsvp_event(self, event_id: str, state: str) -> str:
        return await self.run(ops.rsvp_event(event_id, state))

    async def register_device(
        self, notification_token: str, app_id: str | None = None, sandbox: bool | None = None
    ) -> bool:
        return await self.run(ops.register_device(notification_token, app_id, sandbox))

    async def events(
        self, window: str = "UPCOMING", locale_id: str | None = None, venue_id: str | None = None, first: int = 100
    ) -> list[Event]:
        return await self.run(ops.events(window, locale_id, venue_id, first))

    async def event(self, id: str) -> Event | None:
        return await self.run(ops.event(id))

    async def event_series(
        self, locale_id: str | None = None, venue_id: str | None = None, first: int = 100
    ) -> list[EventSeries]:
        return await self.run(ops.event_series(locale_id, venue_id, first))

    async def cancel_rsvp(self, event_id: str) -> RSVP:
        """Takes back the signed-in person's RSVP, as if they'd never answered."""
        return await self.run(ops.cancel_rsvp(event_id))

    async def community(self) -> Community:
        """Everything the audience lists in one go: the audience, its locales, venues, people, upcoming events and
        event series. A part whose module the audience doesn't have comes back empty."""

        async def optional(read: Callable[[], Awaitable[Any]]) -> Any:
            try:
                return await read()
            except AudienceKitError as error:
                if not error.is_undefined_field:
                    raise
                return None

        reads: list[Callable[[], Awaitable[Any]]] = [
            self.audience,
            self.locales,
            self.venues,
            self.people,
            self.events,
            self.event_series,
        ]
        return _community(list(await asyncio.gather(*(optional(read) for read in reads))))

    # Cover and chat

    async def venue_cover(self, venue_id: str) -> VenueCover | None:
        return await self.run(ops.venue_cover(venue_id))

    async def buy_cover(self, venue_id: str, amount_cents: int | None = None, currency: str = "usd") -> CoverPurchase:
        """Starts paying tonight's cover at a venue: finish with Stripe and ``confirm_cover``, or with a Square
        payment token and ``pay_cover``. ``amount_cents`` is the buyer's choice on a sliding scale."""
        return await self.run(ops.buy_cover(venue_id, amount_cents, currency))

    async def buy_coat_check(self, venue_id: str, quantity: int = 1) -> CoverPurchase:
        return await self.run(ops.buy_coat_check(venue_id, quantity))

    async def pay_cover(self, admission_id: str, source_id: str, verification_token: str | None = None) -> Admission:
        return await self.run(ops.pay_cover(admission_id, source_id, verification_token))

    async def confirm_cover(self, admission_id: str) -> Admission:
        return await self.run(ops.confirm_cover(admission_id))

    async def refund_admission(self, admission_id: str) -> Admission:
        return await self.run(ops.refund_admission(admission_id))

    async def admissions(self) -> list[Admission]:
        return await self.run(ops.admissions())

    async def send_chat_message(
        self, text: str, *, venue_id: str | None = None, locale_id: str | None = None, prompt_id: str | None = None
    ) -> ChatMessage:
        return await self.run(ops.send_chat_message(text, venue_id, locale_id, prompt_id))

    async def remove_chat_message(self, message_id: str) -> None:
        await self.run(ops.remove_chat_message(message_id))

    # Soapbox (news)

    async def articles(
        self, locale_id: str | None = None, publication_id: str | None = None, first: int | None = None
    ) -> list[Article]:
        """The audience's live articles, pinned first, then newest. Empty without Soapbox."""
        return await self.run(ops.articles(locale_id, publication_id, first))

    async def articles_page(
        self, locale_id: str | None = None, publication_id: str | None = None, first: int = 20, after: str | None = None
    ) -> ArticlesPage:
        return await self.run(ops.articles_page(locale_id, publication_id, first, after))

    async def national_articles(self, locale_id: str | None = None, first: int | None = None) -> list[Article]:
        return await self.run(ops.national_articles(locale_id, first))

    async def article(self, id: str) -> Article | None:
        return await self.run(ops.article(id))

    async def articles_about(self, topic: str, id: str, first: int | None = None) -> list[Article]:
        """Live articles about a ``venue``, ``event``, ``person`` or ``locale``: "In the news" on its page."""
        return await self.run(ops.articles_about(topic, id, first))

    async def publications(self) -> list[Publication]:
        return await self.run(ops.publications())

    async def local_publications(self, locale_id: str) -> list[Publication]:
        """The publications covering a locale: the "local publishers" at the top of its news."""
        return [p for p in await self.publications() if p.locale and p.locale.id.lower() == locale_id.lower()]

    async def publication(self, id: str) -> Publication | None:
        return await self.run(ops.publication(id))

    async def my_op_eds(self) -> list[Article]:
        return await self.run(ops.my_op_eds())

    async def submit_op_ed(
        self, publication_id: str, title: str, body: str, *, summary: str | None = None, byline: str | None = None
    ) -> Article:
        return await self.run(ops.submit_op_ed(publication_id, title, body, summary, byline))

    # Calendar subscription

    async def calendar_feed(self) -> CalendarFeed | None:
        return await self.run(ops.calendar_feed())

    async def create_calendar_feed(self, reset: bool = False) -> CalendarFeed:
        """Their calendar subscription, made on first ask; ``reset`` gives it a new link."""
        return await self.run(ops.create_calendar_feed(reset))

    async def follow_venue_in_calendar(self, venue_id: str, following: bool = True) -> CalendarFeed:
        return await self.run(ops.follow_venue_in_calendar(venue_id, following))

    async def delete_calendar_feed(self) -> bool:
        return await self.run(ops.delete_calendar_feed())

    # Moderation and the account

    async def report_content(
        self, target_type: str, id: str, reason: str | None = None, block: bool = False
    ) -> ReportResult:
        """Files a report with the audience's admins; with ``block``, blocks the person behind it. Offer
        ``REPORT_REASONS`` as the reasons."""
        return await self.run(ops.report_content(target_type, id, reason, block))

    async def block_user(self, user_id: str) -> None:
        await self.run(ops.block_user(user_id))

    async def unblock_user(self, user_id: str) -> None:
        await self.run(ops.unblock_user(user_id))

    async def delete_account(self) -> bool:
        """Deletes the signed-in person's account for good and forgets the session. It can't be undone: ask first.
        Returns whether the account is gone; when it isn't, the person stays signed in."""
        deleted = await self.run(ops.delete_account())
        if deleted:
            self._forget("signed_out")
        return deleted

    # Public listings (REST)

    async def public_listings_page(self, page: int = 1) -> PublicListingsPage:
        """One page (from 1) of the audience's public listings: up to 500 venues, then events, then posts. Needs a
        service token with ``public:read``."""
        return PublicListingsPage.from_json(
            await self.request("GET", "/v1/public/listings", params={"page": str(max(1, page))})
        )

    async def public_listings(self) -> list[PublicListing]:
        """Every public listing, page by page."""
        listings: list[PublicListing] = []
        page = 1
        while True:
            found = await self.public_listings_page(page)
            listings.extend(found.listings)
            if found.next_page is None or found.next_page <= page:
                return listings
            page = found.next_page

    async def public_listing(self, kind: str, id: str) -> PublicListing | None:
        """One public listing (``venue``, ``event`` or ``post``), or ``None`` when it's gone."""
        try:
            body = await self.request("GET", self._listing_path(kind, id))
        except AudienceKitError as error:
            if error.code == "NOT_FOUND":
                return None
            raise
        return PublicListing.from_json(body) if isinstance(body, dict) else None

    async def public_tonight(self, venue_id: str) -> JSON:
        """Tonight at a venue, as a screen facing the room shows it: tonight's event, who's on and what's next."""
        body = await self.request("GET", f"/v1/public/venues/{quote(venue_id, safe='')}/tonight")
        return body if isinstance(body, dict) else {}


def _facebook_body(
    configuration: Configuration,
    device: DeviceDescription,
    *,
    facebook_token: str | None = None,
    code: str | None = None,
    redirect_uri: str | None = None,
) -> JSON:
    body: JSON = {"device": device.to_json()}
    if facebook_token is not None:
        body["facebook_token"] = facebook_token
    if code is not None:
        body["code"] = code
    if redirect_uri is not None:
        body["redirect_uri"] = redirect_uri
    if configuration.host:
        body["host"] = configuration.host
    if configuration.facebook_app_id:
        body["facebook_app_id"] = configuration.facebook_app_id
    return body


def _apple_body(
    configuration: Configuration,
    device: DeviceDescription,
    identity_token: str,
    first_name: str | None,
    last_name: str | None,
) -> JSON:
    body: JSON = {"identity_token": identity_token, "device": device.to_json()}
    if first_name is not None:
        body["first_name"] = first_name
    if last_name is not None:
        body["last_name"] = last_name
    if configuration.host:
        body["host"] = configuration.host
    return body


def _present(**values: str | None) -> JSON:
    return {key: value for key, value in values.items() if value is not None}


def _google_body(
    configuration: Configuration,
    device: DeviceDescription,
    id_token: str,
    name: str | None,
    access_token: str | None,
) -> JSON:
    body: JSON = {"id_token": id_token, "device": device.to_json()}
    body.update(_present(name=name, access_token=access_token, host=configuration.host))
    return body


def _review_body(configuration: Configuration, device: DeviceDescription, code: str) -> JSON:
    body: JSON = {"code": code.strip(), "device": device.to_json()}
    body.update(_present(host=configuration.host))
    return body
