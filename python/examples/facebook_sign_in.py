"""Signing people in with Facebook on a server: each browser gets its own AudienceKit session, kept server-side.

    FACEBOOK_APP_ID=… AUDIENCEKIT_HOST=hotmess.social python facebook_sign_in.py

The API trades Facebook's code with the app secret, so the secret never reaches this server. Keep sessions in your
database or framework's session store in production; the dict here is for the example.
"""

from __future__ import annotations

import json
import os
import secrets
from collections.abc import Callable, Iterable
from dataclasses import dataclass, field
from http.cookies import SimpleCookie
from typing import Any
from urllib.parse import parse_qs, urlencode
from wsgiref.simple_server import make_server

import httpx

from audiencekit import AudienceKitError, Client, Configuration, Credential, DeviceDescription

REDIRECT_URI = "http://localhost:8080/auth/facebook"


@dataclass
class BrowserSession:
    """One browser's session: its AudienceKit credential, a device ID, and the state of a sign-in in progress."""

    device_id: str = field(default_factory=lambda: secrets.token_hex(16))
    credential: dict[str, Any] | None = None
    state: str | None = None


def client_for(session: BrowserSession, configuration: Configuration, http: httpx.Client) -> Client:
    """A client acting as this browser's person: it starts from their saved credential and saves every new one. The
    clients share one ``httpx.Client``, so its connections are reused across requests."""

    def keep(event: str, credential: Credential | None) -> None:
        session.credential = credential.to_json() if credential else None

    saved = Credential.from_json(session.credential) if session.credential else None
    return Client(configuration, credential=saved, http=http, on_session_change=keep)


def login_url(session: BrowserSession, facebook_app_id: str, config_id: str | None = None) -> str:
    """Facebook's login dialog, with a fresh state to check when Facebook sends the person back."""
    session.state = secrets.token_urlsafe(24)
    query = {
        "client_id": facebook_app_id,
        "redirect_uri": REDIRECT_URI,
        "state": session.state,
        "response_type": "code",
    }
    if config_id:
        query["config_id"] = config_id
    return f"https://www.facebook.com/v21.0/dialog/oauth?{urlencode(query)}"


def finish_sign_in(client: Client, session: BrowserSession, code: str, state: str) -> bool:
    """Trades Facebook's code for an AudienceKit session, once the state matches the one the dialog was opened with."""
    expected, session.state = session.state, None
    if not expected or not secrets.compare_digest(expected, state):
        return False
    client.sign_in_with_facebook_code(code, REDIRECT_URI, DeviceDescription(session.device_id, type="web"))
    return True


def make_app(
    configuration: Configuration, sessions: dict[str, BrowserSession], http: httpx.Client | None = None
) -> Callable[..., Any]:
    """The WSGI app: ``/`` says who's signed in, ``/sign-in`` opens Facebook, ``/auth/facebook`` finishes."""
    shared = http or httpx.Client(timeout=30.0)

    def app(environ: dict[str, Any], start_response: Callable[..., Any]) -> Iterable[bytes]:
        cookie = SimpleCookie(environ.get("HTTP_COOKIE", ""))
        sid = cookie["sid"].value if "sid" in cookie and cookie["sid"].value in sessions else secrets.token_urlsafe(24)
        session = sessions.setdefault(sid, BrowserSession())
        headers = [("Set-Cookie", f"sid={sid}; HttpOnly; SameSite=Lax; Path=/")]
        path, query = environ.get("PATH_INFO", "/"), parse_qs(environ.get("QUERY_STRING", ""))

        def respond(status: str, body: str = "", location: str | None = None) -> list[bytes]:
            extra = [("Location", location)] if location else [("Content-Type", "text/plain; charset=utf-8")]
            start_response(status, headers + extra)
            return [body.encode()]

        client = client_for(session, configuration, shared)
        if path == "/sign-in":
            branding = client.branding()
            config_id = branding.facebook_login_config_id
            return respond("302 Found", location=login_url(session, configuration.facebook_app_id or "", config_id))
        if path == "/auth/facebook":
            code, state = query.get("code", [""])[0], query.get("state", [""])[0]
            if not finish_sign_in(client, session, code, state):
                return respond("400 Bad Request", "That sign-in link has expired. Try again.")
            # A new session ID, so the one that carried the sign-in isn't the one that carries the credential.
            sessions[new_sid := secrets.token_urlsafe(24)] = sessions.pop(sid)
            headers[0] = ("Set-Cookie", f"sid={new_sid}; HttpOnly; SameSite=Lax; Path=/")
            return respond("302 Found", location="/")
        if not client.is_signed_in:
            return respond("200 OK", "Not signed in. Visit /sign-in.")
        try:
            me = client.me()
        except AudienceKitError as error:
            if error.is_unauthenticated:
                return respond("302 Found", location="/sign-in")
            raise
        return respond("200 OK", json.dumps({"signed_in_as": me.name if me else None}))

    return app


if __name__ == "__main__":
    configuration = Configuration(
        host=os.environ.get("AUDIENCEKIT_HOST"), facebook_app_id=os.environ["FACEBOOK_APP_ID"]
    )
    print("http://localhost:8080/sign-in")
    make_server("", 8080, make_app(configuration, {})).serve_forever()
