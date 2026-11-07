"""A fake AudienceKit API behind ``httpx.MockTransport``, so the tests see every request the client sends."""

from __future__ import annotations

import json
from collections.abc import Callable
from dataclasses import dataclass, field
from typing import Any

import httpx
import pytest

from audiencekit import AsyncClient, Client, Configuration, Credential

AUDIENCE_ID = "6f9f4c7a-1111-4a2b-9c3d-000000000001"
TOKEN = "jwt-session-token"
ENDPOINT = f"https://api.audiencekit.com/v1/audience/{AUDIENCE_ID}/graphql"

CREDENTIAL_JSON = {
    "token": TOKEN,
    "userId": "user-1",
    "audienceId": AUDIENCE_ID,
    "role": "member",
    "endpoint": ENDPOINT,
    "venueDeviceId": None,
    "expiresAt": None,
}

Handler = Callable[[httpx.Request, dict[str, Any] | None], httpx.Response]


@dataclass
class FakeAPI:
    """Answers each GraphQL operation by name and each REST path by ``METHOD /path``; records every request."""

    operations: dict[str, Any] = field(default_factory=dict)
    rest: dict[str, Any] = field(default_factory=dict)
    requests: list[httpx.Request] = field(default_factory=list)
    bodies: list[dict[str, Any] | None] = field(default_factory=list)
    # Fields each introspected type has, for the SchemaFields operation.
    schema: dict[str, list[str]] = field(default_factory=dict)

    def transport(self) -> httpx.MockTransport:
        return httpx.MockTransport(self.handle)

    def async_transport(self) -> httpx.MockTransport:
        return httpx.MockTransport(self.handle)

    def handle(self, request: httpx.Request) -> httpx.Response:
        self.requests.append(request)
        body = json.loads(request.content) if request.content else None
        self.bodies.append(body)
        key = f"{request.method} {request.url.path}"
        if key in self.rest:
            answer = self.rest[key]
            return answer(request, body) if callable(answer) else answer
        if request.method == "POST" and request.url.path.startswith("/v1/audience/"):
            return self.graphql(request, body or {})
        return httpx.Response(404, json={"error": "not_found", "message": f"No route {key}"})

    def graphql(self, request: httpx.Request, body: dict[str, Any]) -> httpx.Response:
        name = body.get("operationName")
        if name == "SchemaFields" and "SchemaFields" not in self.operations:
            return self.introspect(body["query"])
        answer = self.operations.get(name)
        if answer is None:
            return httpx.Response(200, json={"errors": [{"message": f"Unexpected operation {name}"}]})
        if callable(answer):
            answer = answer(request, body)
        if isinstance(answer, httpx.Response):
            return answer
        return httpx.Response(200, json=answer)

    def introspect(self, query: str) -> httpx.Response:
        """``t0: __type(name: "Venue") { … }`` for each type the client asked about."""
        data: dict[str, Any] = {}
        for part in query.split("__type(name: ")[1:]:
            name = part.split('"')[1]
            alias = f"t{len(data)}"
            fields = self.schema.get(name)
            data[alias] = None if fields is None else {"fields": [{"name": f} for f in fields]}
        return httpx.Response(200, json={"data": data})

    @property
    def last_body(self) -> dict[str, Any] | None:
        return self.bodies[-1]

    @property
    def last(self) -> httpx.Request:
        return self.requests[-1]

    def operation_names(self) -> list[str]:
        return [str(b.get("operationName")) for b in self.bodies if b and "operationName" in b]


def undefined_field(field_name: str = "profile", type_name: str = "Venue") -> dict[str, Any]:
    return {
        "errors": [
            {
                "message": f"Field '{field_name}' doesn't exist on type '{type_name}'",
                "extensions": {"code": "undefinedField", "typeName": type_name, "fieldName": field_name},
            }
        ]
    }


@pytest.fixture
def api() -> FakeAPI:
    return FakeAPI()


@pytest.fixture
def credential() -> Credential:
    return Credential.from_json(CREDENTIAL_JSON)


@pytest.fixture
def client(api: FakeAPI, credential: Credential) -> Client:
    """A signed-in blocking client on the fake API."""
    return Client(
        Configuration(host="hotmess.social"), credential=credential, http=httpx.Client(transport=api.transport())
    )


@pytest.fixture
def anonymous(api: FakeAPI) -> Client:
    """A blocking client before sign-in, with a configured audience."""
    return Client(
        Configuration(host="hotmess.social", audience_id=AUDIENCE_ID), http=httpx.Client(transport=api.transport())
    )


@pytest.fixture
def async_client(api: FakeAPI, credential: Credential) -> AsyncClient:
    return AsyncClient(
        Configuration(host="hotmess.social"),
        credential=credential,
        http=httpx.AsyncClient(transport=api.async_transport()),
    )
