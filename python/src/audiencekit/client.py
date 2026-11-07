"""The clients: ``Client`` (blocking) and ``AsyncClient`` (asyncio), on httpx.

Both talk to the AudienceKit API on behalf of one audience and one signed-in person. Hand ``sign_in_with_facebook``
a Facebook access token the app obtained (or ``adopt`` a credential minted elsewhere, such as a service token); every
call then carries ``Authorization: Bearer <token>``, the API contract version and the client's name. When the API
rejects the token (HTTP 401) the credential is forgotten and the call raises ``AudienceKitError`` with the
``UNAUTHENTICATED`` code.
"""

from __future__ import annotations

import json
from collections.abc import Callable
from typing import Any, TypeVar

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
    Audience,
    Branding,
    Coordinate,
    Event,
    EventSeries,
    Locale,
    Node,
    Person,
    SelfUser,
    TribeIdentification,
    Tribes,
    Venue,
)
from .operations import Operation
from .schema import EVERYTHING, SchemaShape

T = TypeVar("T")

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
        token = self._token_for(request)
        return self._rest_result(self._send(request, token=token), token)

    # Session

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
    ) -> Credential:
        """Exchanges a Sign in with Apple identity token for a session. Apple gives the person's name only the first
        time; pass it then."""
        return self._sign_in(
            "/v1/token/apple", _apple_body(self.configuration, device, identity_token, first_name, last_name)
        )

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
        if self._credential is None:
            raise AudienceKitError.not_signed_in()
        self.audience_id()
        request, base = self._graphql_request(query, variables, operation_name, endpoint)
        token = self._token_for(request)
        body = self._rest_result(self._send(request, token=token, base_url=base), token)
        return self._graphql_result(body)

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
        token = self._token_for(request)
        return self._rest_result(await self._send(request, token=token), token)

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
    ) -> Credential:
        return await self._sign_in(
            "/v1/token/apple", _apple_body(self.configuration, device, identity_token, first_name, last_name)
        )

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
        if self._credential is None:
            raise AudienceKitError.not_signed_in()
        await self.audience_id()
        request, base = self._graphql_request(query, variables, operation_name, endpoint)
        token = self._token_for(request)
        body = self._rest_result(await self._send(request, token=token, base_url=base), token)
        return self._graphql_result(body)

    async def schema_fields(self, types: list[str], endpoint: str = CONSUMER_ENDPOINT) -> SchemaShape:
        missing = self._missing_types(types, endpoint)
        if missing:
            data = await self.graphql(queries.schema_fields(missing), operation_name="SchemaFields", endpoint=endpoint)
            self._remember_schema(missing, endpoint, data)
        return self._cached_shape(types, endpoint) or SchemaShape({})

    async def run(self, operation: Operation[T], endpoint: str = CONSUMER_ENDPOINT) -> T:
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
