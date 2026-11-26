# Signing people in with Node

A website or app backend signs a person in with a provider (Facebook, Google or Apple), hands what the provider
returned to AudienceKit, and keeps the AudienceKit session it gets back. From then on every call the client makes acts
as that person, under the audience's rules: they see what members see, and their RSVPs, chat messages and cover passes
are their own.

A site that only shows what the audience lists publicly doesn't sign anyone in; see
[Building a website](websites.md) for service tokens.

## One session per browser

A server talks to AudienceKit for many people at once, so make an `AudienceKitClient` per request, over a `TokenStore`
that reads and writes that person's session, wherever your server keeps sessions (a signed cookie session, Redis, a
database row):

```ts
import { AudienceKitClient, type TokenStore } from "audience-kit";

/** The AudienceKit token and audience, kept in the visitor's server-side session. */
class SessionTokenStore implements TokenStore {
  constructor(private readonly session: { audienceKitToken?: string | null; audienceId?: string | null }) {}
  loadToken() { return this.session.audienceKitToken ?? null; }
  saveToken(token: string) { this.session.audienceKitToken = token; }
  deleteToken() { this.session.audienceKitToken = null; this.session.audienceId = null; }
  loadAudienceId() { return this.session.audienceId ?? null; }
  saveAudienceId(id: string | null) { this.session.audienceId = id; }
}

function audienceKit(session: Session) {
  return new AudienceKitClient({
    configuration: {
      host: "hotmess.social",        // the host that names your audience
      facebookAppId: "123456789",    // the Facebook app your login dialog uses
    },
    tokenStore: new SessionTokenStore(session),
  });
}
```

The token is as good as a password: keep it on the server, never in `localStorage` or a cookie the browser can read,
and never log it. `client.isSignedIn()` says whether there's a session, `client.me()` reads the person's profile.

Every sign-in takes a `DeviceDescription`: a stable identifier for the browser or server (a random one kept in the
session works), and its type, `web` for a browser behind your server:

```ts
const device = { identifier: session.deviceId ??= crypto.randomUUID(), type: "web" };
```

After a sign-in succeeds, give the visitor a new session ID (`req.session.regenerate()` in Express), so the ID that
carried the sign-in isn't the one that carries the credential.

## Facebook

Open Facebook's login dialog (for Facebook Login for Business, with the configuration ID the audience's branding gives
as `facebook_login_config_id`), and when Facebook redirects back with a `code`, trade it. The redirect URI must be
exactly the one the dialog was opened with:

```ts
const branding = await client.branding();   // public: the audience, its theme and its login configuration

// 1. Send the person to Facebook.
session.oauthState = crypto.randomUUID();
const query = new URLSearchParams({
  client_id: "123456789",
  redirect_uri: "https://example.com/auth/facebook",
  state: session.oauthState,
  response_type: "code",
});
if (branding.facebook_login_config_id) query.set("config_id", branding.facebook_login_config_id);
res.redirect(`https://www.facebook.com/v21.0/dialog/oauth?${query}`);

// 2. On https://example.com/auth/facebook:
if (!session.oauthState || req.query.state !== session.oauthState) return res.sendStatus(400);
session.oauthState = null;
await client.signInWithFacebookCode(String(req.query.code), "https://example.com/auth/facebook", device);
```

The API trades the code with the app secret, so the secret never reaches your server. When the dialog belongs to
another Facebook app than the configured one, pass its ID as the fourth argument. A Facebook user access token the
browser got from the JavaScript SDK works too: `client.signIn(accessToken, device)`.

[`examples/facebook-sign-in.ts`](../examples/facebook-sign-in.ts) is the whole flow as a server you can run, with a
session per browser and a timing-safe state check.

## Google

Google Identity Services posts an ID token (its `credential`) to your login endpoint. Check its CSRF cookie, then trade
it:

```ts
if (!req.body.g_csrf_token || req.body.g_csrf_token !== req.cookies.g_csrf_token) return res.sendStatus(400);
await client.signInWithGoogle(req.body.credential, device);
```

The ID token carries only the account's primary email. To let the API match an existing account by the Google
account's other verified emails, also ask for the `https://www.googleapis.com/auth/user.emails.read` scope and pass the
access token: `signInWithGoogle(idToken, device, { accessToken })`. A person already signed in can add Google to their
account with `connectGoogle(idToken, device)`.

## Sign in with Apple

Sign in with Apple JS returns an identity token, an authorization code and, the first time only, the person's name.
Pass them with the redirect URI and the nonce you gave Apple:

```ts
await client.signInWithApple(
  {
    identityToken: response.authorization.id_token,
    authorizationCode: response.authorization.code,
    redirectUri: "https://example.com/auth/apple",
    nonce: session.appleNonce,
    firstName: response.user?.name?.firstName ?? null,
    lastName: response.user?.name?.lastName ?? null,
  },
  device,
);
```

## App Review codes

While an audience is in App Review, its console issues a code a reviewer types instead of signing in with a provider:

```ts
await client.signInWithReviewCode(req.body.code, device);
```

A wrong or expired code throws `AudienceKitError` with code `SIGN_IN_REJECTED`.

## When sessions end

A session ends when the person signs out elsewhere, removes the app from Facebook, or an admin ends it. When the API
refuses it, the call throws `AudienceKitError` with code `UNAUTHORIZED` (`error.isUnauthenticated`), the client forgets
the token, and `onSession` listeners get `sessionEnded`: send the person back to sign in.

```ts
import { AudienceKitError } from "audience-kit";

try {
  res.json(await client.admissions());
} catch (error) {
  if (error instanceof AudienceKitError && error.isUnauthenticated) return res.redirect("/sign-in");
  throw error;
}
```

`refreshSession()` re-issues the token for the same session (after the API rotates its signing key, say).
`signOut()` forgets it; log the person out of Facebook or Google too if your site signed them in there.

## Deleting an account

App stores and privacy law expect people to be able to delete their account from wherever they signed up. After the
person confirms:

```ts
if (await client.deleteAccount()) req.session.destroy(() => res.redirect("/"));
```

It erases their data in the audience and signs them out everywhere, and can't be undone. When it returns false the
person is still signed in.
