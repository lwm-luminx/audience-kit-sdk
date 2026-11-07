"""Everything a client call can fail with."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

# The API's vocabulary, sent as ``extensions.code`` on GraphQL errors and as ``error`` on REST ones.
UNAUTHENTICATED = "UNAUTHENTICATED"
FORBIDDEN = "FORBIDDEN"
NOT_FOUND = "NOT_FOUND"
INVALID = "INVALID"
RATE_LIMITED = "RATE_LIMITED"
CONFLICT = "CONFLICT"
INTERNAL = "INTERNAL"

# Raised by the SDK itself.
NOT_SIGNED_IN = "NOT_SIGNED_IN"
SIGN_IN_REJECTED = "SIGN_IN_REJECTED"
SIGN_IN_FAILED = "SIGN_IN_FAILED"
HTTP = "HTTP"
NETWORK = "NETWORK"
DECODING = "DECODING"
GRAPHQL = "GRAPHQL"
MISSING_CONFIGURATION = "MISSING_CONFIGURATION"
UPDATE_REQUIRED = "UPDATE_REQUIRED"
UNSUPPORTED_API_VERSION = "UNSUPPORTED_API_VERSION"

UNSUPPORTED_API_VERSION_BODY = "unsupported_api_version"


@dataclass(frozen=True)
class GraphQLError:
    """One entry of a GraphQL response's ``errors`` array."""

    message: str
    path: list[Any] | None = None
    extensions: dict[str, Any] | None = None

    @property
    def code(self) -> str | None:
        """``extensions.code``, when the API sent one."""
        code = (self.extensions or {}).get("code")
        return code if isinstance(code, str) else None

    @classmethod
    def from_json(cls, data: dict[str, Any]) -> GraphQLError:
        return cls(
            message=str(data.get("message", "")),
            path=data.get("path"),
            extensions=data.get("extensions"),
        )


@dataclass
class AudienceKitError(Exception):
    """A failed call: a ``code`` from the API's vocabulary (or the SDK's own), a message, and what detail there is.

    ``fields`` holds the API's per-field messages for ``INVALID`` errors, ``errors`` the GraphQL response's errors
    when the operation returned any, ``status`` the HTTP status when there was a response, and
    ``minimum_sdk_version`` the oldest SDK the API still serves for ``UPDATE_REQUIRED``.
    """

    code: str
    message: str
    status: int | None = None
    fields: dict[str, list[str]] = field(default_factory=dict)
    errors: list[GraphQLError] = field(default_factory=list)
    minimum_sdk_version: str | None = None

    def __str__(self) -> str:
        return self.message

    @property
    def is_unauthenticated(self) -> bool:
        return self.code == UNAUTHENTICATED

    @property
    def is_undefined_field(self) -> bool:
        """The API refused the query because it asks for a field this audience's schema doesn't have."""
        return any(error.code == "undefinedField" for error in self.errors)

    # Values the SDK raises.

    @classmethod
    def not_signed_in(cls) -> AudienceKitError:
        return cls(NOT_SIGNED_IN, "You're not signed in.")

    @classmethod
    def unauthorized(cls) -> AudienceKitError:
        return cls(UNAUTHENTICATED, "Your session has ended. Sign in again to continue.", status=401)

    @classmethod
    def sign_in_rejected(cls) -> AudienceKitError:
        return cls(SIGN_IN_REJECTED, "Sign-in was refused. The login isn't valid for this app.", status=401)

    @classmethod
    def sign_in_failed(cls, message: str | None) -> AudienceKitError:
        return cls(SIGN_IN_FAILED, message or "Sign-in failed.", status=400)

    @classmethod
    def forbidden(cls, message: str | None = None) -> AudienceKitError:
        return cls(FORBIDDEN, message or "You don't have access to this.", status=403)

    @classmethod
    def not_found(cls, message: str | None = None) -> AudienceKitError:
        return cls(NOT_FOUND, message or "That isn't available.", status=404)

    @classmethod
    def http(cls, status: int, code: str | None = None, message: str | None = None) -> AudienceKitError:
        return cls(code or HTTP, message or f"The server responded with status {status}.", status=status)

    @classmethod
    def network(cls, detail: str) -> AudienceKitError:
        return cls(NETWORK, detail)

    @classmethod
    def decoding(cls, detail: str) -> AudienceKitError:
        return cls(DECODING, f"The server sent a response the app didn't understand. {detail}")

    @classmethod
    def missing_configuration(cls, detail: str) -> AudienceKitError:
        return cls(MISSING_CONFIGURATION, f"AudienceKit isn't configured: {detail}")

    @classmethod
    def update_required(cls, minimum_sdk_version: str, message: str | None) -> AudienceKitError:
        return cls(
            UPDATE_REQUIRED,
            message or "This version of the app is out of date. Update it to keep going.",
            status=426,
            minimum_sdk_version=minimum_sdk_version,
        )

    @classmethod
    def graphql(cls, errors: list[GraphQLError]) -> AudienceKitError:
        """The operation returned ``errors``: the code and message are the first one's, and ``INVALID`` errors'
        ``extensions.fields`` become ``fields``."""
        first = errors[0] if errors else None
        fields: dict[str, list[str]] = {}
        extensions = (first.extensions if first else None) or {}
        sent_fields = extensions.get("fields")
        if isinstance(sent_fields, dict):
            for name, value in sent_fields.items():
                if isinstance(value, list):
                    fields[name] = [item for item in value if isinstance(item, str)]
                elif isinstance(value, str):
                    fields[name] = [value]
        code = first.code if first and first.code else GRAPHQL
        message = first.message if first and first.message else "The request failed."
        return cls(code, message, fields=fields, errors=errors)

    @classmethod
    def for_status(cls, status: int, body: Any) -> AudienceKitError:
        """The error for an unsuccessful REST status, reading ``{"error": "<code>", "message": "…"}`` when sent."""
        body = body if isinstance(body, dict) else {}
        fault = body.get("fault") if isinstance(body.get("fault"), dict) else {}
        message = body.get("message") or fault.get("message")
        message = message if isinstance(message, str) else None
        error = body.get("error") if isinstance(body.get("error"), str) else None

        if status == 401:
            return cls.unauthorized()
        if status == 403:
            return cls.forbidden(message)
        if status == 404:
            return cls.not_found(message)
        if status == 400 and error == UNSUPPORTED_API_VERSION_BODY:
            text = message or "This version of the app is out of date. Update it to keep going."
            supported = body.get("supported")
            if isinstance(supported, list) and supported:
                text += f" (API versions served: {', '.join(str(v) for v in supported)}.)"
            return cls(UNSUPPORTED_API_VERSION, text, status=400)
        if status == 426:
            minimum = body.get("minimum_sdk_version")
            return cls.update_required(minimum if isinstance(minimum, str) else "", message)

        codes = {400: INVALID, 409: CONFLICT, 422: INVALID, 429: RATE_LIMITED}
        code = error.upper() if error else codes.get(status)
        if code is None and status >= 500:
            code = INTERNAL
        return cls.http(status, code, message)
