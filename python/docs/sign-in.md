# Signing people in with Python

A website or app backend signs a person in with a provider (Facebook, Google or Apple), hands what the provider
returned to AudienceKit, and keeps the AudienceKit session it gets back. From then on every call the client makes acts
as that person, under the audience's rules: they see what members see, and their RSVPs, chat messages and cover passes
are their own.

A site that only shows what the audience lists publicly doesn't sign anyone in; see
[Building a website](websites.md) for service tokens.

## One session per browser

A server talks to AudienceKit for many people at once, so make a `Client` per request, starting from the credential
kept in that person's server-side session (Django's or Flask's session, Redis, a database row), and save every new one
with `on_session_change`. Share one `httpx.Client` between them, so connections are reused:

```python
import httpx
from audiencekit import Client, Configuration, Credential

CONFIGURATION = Configuration(
    host="hotmess.social",  # the host that names your audience
    facebook_app_id="123456789",  # the Facebook app your login dialog uses
)
HTTP = httpx.Client(timeout=30.0)


def audiencekit(session) -> Client:
    def keep(event: str, credential: Credential | None) -> None:
        session["audiencekit"] = credential.to_json() if credential else None

    saved = session.get("audiencekit")
    return Client(
        CONFIGURATION,
        credential=Credential.from_json(saved) if saved else None,
        http=HTTP,
        on_session_change=keep,
    )
```

The listener hears `"signed_in"` with the new credential, and `"signed_out"` or `"session_ended"` with `None`. The
token is as good as a password: keep it on the server, never in a cookie the browser can read, and never log it.
`client.is_signed_in` says whether there's a session, `client.me()` reads the person's profile.

Every sign-in takes a `DeviceDescription`: a stable identifier for the browser or server (a random one kept in the
session works), and its type, `web` for a browser behind your server:

```python
import secrets
from audiencekit import DeviceDescription

device = DeviceDescription(session.setdefault("device_id", secrets.token_hex(16)), type="web")
```

After a sign-in succeeds, give the visitor a new session ID (`request.session.cycle_key()` in Django), so the ID that
carried the sign-in isn't the one that carries the credential.

## Facebook

Open Facebook's login dialog (for Facebook Login for Business, with the configuration ID the audience's branding gives
as `facebook_login_config_id`), and when Facebook redirects back with a `code`, trade it. The redirect URI must be
exactly the one the dialog was opened with:

```python
from urllib.parse import urlencode

branding = client.branding()  # public: the audience, its theme and its login configuration

# 1. Send the person to Facebook.
session["oauth_state"] = secrets.token_urlsafe(24)
query = {
    "client_id": "123456789",
    "redirect_uri": "https://example.com/auth/facebook",
    "state": session["oauth_state"],
    "response_type": "code",
}
if branding.facebook_login_config_id:
    query["config_id"] = branding.facebook_login_config_id
return redirect(f"https://www.facebook.com/v21.0/dialog/oauth?{urlencode(query)}")

# 2. On https://example.com/auth/facebook:
expected = session.pop("oauth_state", None)
if not expected or not secrets.compare_digest(expected, request.args["state"]):
    abort(400)
client.sign_in_with_facebook_code(request.args["code"], "https://example.com/auth/facebook", device)
```

The API trades the code with the app secret, so the secret never reaches your server. A Facebook user access token
the browser got from the JavaScript SDK works too: `client.sign_in_with_facebook(access_token, device)`. A person who
signed in with Apple can add Facebook to their account with `connect_facebook(code, redirect_uri, device)`.

[`examples/facebook_sign_in.py`](../examples/facebook_sign_in.py) is the whole flow as a WSGI app you can run, with a
session per browser and a timing-safe state check.

## Google

Google Identity Services posts an ID token (its `credential`) to your login endpoint. Check its CSRF cookie, then trade
it:

```python
token = request.form.get("g_csrf_token")
if not token or token != request.cookies.get("g_csrf_token"):
    abort(400)
client.sign_in_with_google(request.form["credential"], device)
```

The ID token carries only the account's primary email. To let the API match an existing account by the Google
account's other verified emails, also ask for the `https://www.googleapis.com/auth/user.emails.read` scope and pass the
access token: `sign_in_with_google(id_token, device, access_token=access_token)`. A person already signed in can add
Google to their account with `connect_google(id_token, device)`.

## Sign in with Apple

Sign in with Apple JS returns an identity token, an authorization code and, the first time only, the person's name.
Pass them with the redirect URI and the nonce you gave Apple:

```python
client.sign_in_with_apple(
    form["id_token"],
    device,
    authorization_code=form["code"],
    redirect_uri="https://example.com/auth/apple",
    nonce=session.pop("apple_nonce"),
    first_name=user.get("name", {}).get("firstName"),
    last_name=user.get("name", {}).get("lastName"),
)
```

## App Review codes

While an audience is in App Review, its console issues a code a reviewer types instead of signing in with a provider:

```python
client.sign_in_with_review_code(request.form["code"], device)
```

A wrong or expired code raises `AudienceKitError` with code `SIGN_IN_REJECTED`.

## When sessions end

A session ends when the person signs out elsewhere, removes the app from Facebook, or an admin ends it. When the API
refuses it, the call raises `AudienceKitError` with code `UNAUTHENTICATED` (`error.is_unauthenticated`), the client
forgets the credential, and your listener hears `"session_ended"`: send the person back to sign in.

```python
from audiencekit import AudienceKitError

try:
    passes = client.admissions()
except AudienceKitError as error:
    if error.is_unauthenticated:
        return redirect("/sign-in")
    raise
```

`refresh_session()` re-issues the token for the same session (after the API rotates its signing key, say).
`sign_out()` forgets it; log the person out of Facebook or Google too if your site signed them in there.

## Deleting an account

App stores and privacy law expect people to be able to delete their account from wherever they signed up. After the
person confirms:

```python
if client.delete_account():
    session.clear()
```

It erases their data in the audience and signs them out everywhere, and can't be undone. When it returns `False` the
person is still signed in.

## asyncio

`AsyncClient` takes the same calls and arguments, awaited, over an `httpx.AsyncClient`, for FastAPI, Starlette or
aiohttp:

```python
async with AsyncClient(CONFIGURATION, credential=saved) as client:
    await client.sign_in_with_google(id_token, device)
```
