"""A session the API issued."""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any

from .config import API_VERSION, origin
from .models import parse_datetime


@dataclass(frozen=True)
class Credential:
    """A session the API issued, as ``POST /v1/token`` returns it.

    It says everything the client needs: which audience it is for, which GraphQL endpoint it was issued for (its
    origin is the API instance to talk to), the user's role, and when it expires, if ever. Treat ``token`` like a
    password and never log it.
    """

    token: str
    user_id: str
    role: str
    endpoint: str
    audience_id: str | None = None
    venue_device_id: str | None = None
    expires_at: datetime | None = None
    api_version: str = API_VERSION

    @property
    def origin(self) -> str:
        """The API instance that issued the credential: its endpoint's origin."""
        return origin(self.endpoint)

    @classmethod
    def from_json(cls, data: dict[str, Any]) -> Credential:
        return cls(
            token=str(data["token"]),
            user_id=str(data["userId"]),
            role=str(data.get("role") or "member"),
            endpoint=str(data["endpoint"]),
            audience_id=data.get("audienceId"),
            venue_device_id=data.get("venueDeviceId"),
            expires_at=parse_datetime(data.get("expiresAt")),
            api_version=str(data.get("apiVersion") or API_VERSION),
        )

    def to_json(self) -> dict[str, Any]:
        """The credential as the API serializes it, for storing it between runs."""
        return {
            "token": self.token,
            "userId": self.user_id,
            "audienceId": self.audience_id,
            "role": self.role,
            "endpoint": self.endpoint,
            "venueDeviceId": self.venue_device_id,
            "expiresAt": self.expires_at.isoformat().replace("+00:00", "Z") if self.expires_at else None,
            "apiVersion": self.api_version,
        }
