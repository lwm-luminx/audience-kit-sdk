"""Where the SDK talks to and which audience it speaks for."""

from __future__ import annotations

from dataclasses import dataclass, field
from urllib.parse import urlsplit

PRODUCTION_BASE_URL = "https://api.audiencekit.com"
"""The hosted AudienceKit API."""

API_VERSION = "2026-10-11"
"""The API contract this SDK speaks, the date it was last broken: sent as ``X-AudienceKit-API-Version``."""

API_VERSION_HEADER = "X-AudienceKit-API-Version"
ENVIRONMENT_HEADER = "X-AudienceKit-Environment"
CLIENT_HEADER = "X-AudienceKit-Client"

CONSUMER_ENDPOINT = "graphql"
"""The consumer view's path segment under ``/v1/audience/<id>/``: the one for the apps people use."""


def endpoint_path(audience_id: str, endpoint: str = CONSUMER_ENDPOINT) -> str:
    """The GraphQL endpoint's path for an audience, e.g. ``/v1/audience/<id>/graphql``."""
    return f"/v1/audience/{audience_id}/{endpoint}"


def same_origin(a: str, b: str) -> bool:
    """Whether two URLs name the same API instance: scheme, host and port (443 when unsaid)."""
    left, right = urlsplit(a), urlsplit(b)
    return (
        (left.scheme or "").lower() == (right.scheme or "").lower()
        and (left.hostname or "").lower() == (right.hostname or "").lower()
        and (left.port or 443) == (right.port or 443)
    )


def origin(url: str) -> str:
    """The origin of a URL: ``https://host[:port]``."""
    parts = urlsplit(url)
    return f"{parts.scheme}://{parts.netloc}"


@dataclass(frozen=True)
class Configuration:
    """Where the SDK talks to and which audience it speaks for.

    ``base_url`` is the API's base URL. ``host`` names the audience (e.g. ``hotmess.social``); it is sent with sign-in
    and used to look up branding. ``audience_id`` is the audience's UUID; when unset the client reads it from the
    credential, or asks ``/v1/branding`` for ``host``. ``environment`` is ``production`` or ``staging``: staging builds
    sign in with the audience's staging Facebook app and say so with the environment header.
    ``trusted_credential_origins`` are other API instances whose credentials ``base_url`` also accepts (its
    ``TRUSTED_API_ORIGIN``): a credential one of them issued is sent to ``base_url`` rather than its own instance.
    """

    base_url: str = PRODUCTION_BASE_URL
    host: str | None = None
    audience_id: str | None = None
    facebook_app_id: str | None = None
    environment: str = "production"
    trusted_credential_origins: tuple[str, ...] = field(default_factory=tuple)

    def api_base(self, credential_endpoint: str | None) -> str:
        """The API instance to send a credential to: the one that issued it, unless ``base_url`` trusts that one."""
        if credential_endpoint is None:
            return self.base_url
        issued_by = origin(credential_endpoint)
        if any(same_origin(trusted, issued_by) for trusted in self.trusted_credential_origins):
            return self.base_url
        return issued_by


@dataclass(frozen=True)
class DeviceDescription:
    """The device a session is created on; the API records it alongside the session."""

    identifier: str
    type: str = "python"
    model: str | None = None
    version: str | None = None
    build: str | None = None

    def to_json(self) -> dict[str, str]:
        body = {"identifier": self.identifier, "type": self.type}
        for key in ("model", "version", "build"):
            value = getattr(self, key)
            if value is not None:
                body[key] = value
        return body
