from __future__ import annotations

from audiencekit import Configuration, Credential, DeviceDescription
from audiencekit.config import endpoint_path, origin, same_origin
from tests.conftest import CREDENTIAL_JSON


def test_endpoint_path() -> None:
    assert endpoint_path("abc") == "/v1/audience/abc/graphql"
    assert endpoint_path("abc", "staff") == "/v1/audience/abc/staff"


def test_same_origin_ignores_paths_and_default_ports() -> None:
    assert same_origin("https://api.audiencekit.com/v1", "HTTPS://API.AUDIENCEKIT.COM:443/other")
    assert not same_origin("https://api.audiencekit.com", "https://next.audiencekit.com")
    assert not same_origin("http://localhost:3000", "http://localhost:3001")
    assert origin("https://api.audiencekit.com/v1/x?y=1") == "https://api.audiencekit.com"


def test_api_base_follows_the_credential_unless_trusted() -> None:
    configuration = Configuration(
        base_url="https://next.audiencekit.com", trusted_credential_origins=("https://api.audiencekit.com",)
    )
    assert configuration.api_base(None) == "https://next.audiencekit.com"
    assert configuration.api_base("https://api.audiencekit.com/v1/audience/a/graphql") == "https://next.audiencekit.com"
    assert configuration.api_base("https://other.example/v1/audience/a/graphql") == "https://other.example"
    plain = Configuration()
    assert plain.api_base("https://next.audiencekit.com/v1/audience/a/graphql") == "https://next.audiencekit.com"


def test_device_description_json_leaves_out_unset_fields() -> None:
    assert DeviceDescription("abc").to_json() == {"identifier": "abc", "type": "python"}
    full = DeviceDescription("abc", type="server", model="m", version="1.0", build="7").to_json()
    assert full == {"identifier": "abc", "type": "server", "model": "m", "version": "1.0", "build": "7"}


def test_credential_round_trips_through_json() -> None:
    credential = Credential.from_json(
        {**CREDENTIAL_JSON, "expiresAt": "2027-01-01T00:00:00Z", "apiVersion": "2026-10-11"}
    )
    assert credential.origin == "https://api.audiencekit.com"
    assert credential.expires_at is not None and credential.expires_at.year == 2027
    again = Credential.from_json(credential.to_json())
    assert again == credential
    assert credential.to_json()["expiresAt"] == "2027-01-01T00:00:00Z"
    minimal = Credential.from_json({"token": "t", "userId": "u", "endpoint": "https://x.example/v1/audience/a/graphql"})
    assert minimal.role == "member" and minimal.audience_id is None and minimal.to_json()["expiresAt"] is None
