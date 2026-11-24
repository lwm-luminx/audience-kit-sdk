# Signing people in with PHP

A website signs a person in with a provider (Facebook, Google or Apple), hands what the provider returned to
AudienceKit, and keeps the AudienceKit session it gets back. From then on every call the SDK makes acts as that person,
under the audience's rules: they see what members see, and their RSVPs, chat messages and cover passes are their own.

A site that only shows what the audience lists publicly doesn't sign anyone in; see
[Building a website](websites.md) for service tokens.

## Set up the session

Make one `AudienceSession` per request, with a `SessionCredentialStore` so the credential lives in PHP's session on
the server rather than in the browser:

```php
use AudienceKit\AudienceSession;
use AudienceKit\Configuration;
use AudienceKit\SessionCredentialStore;

session_set_cookie_params(['secure' => true, 'httponly' => true, 'samesite' => 'Lax']);
session_start();

$audienceKit = new AudienceSession(
    new Configuration(
        host: 'hotmess.social',          // the host that names your audience
        facebookAppId: '123456789',      // the Facebook app your login dialog uses
    ),
    new SessionCredentialStore(),
);
```

`$audienceKit->isSignedIn()` says whether there is a session; `$audienceKit->me()` reads the person's profile. Every
sign-in takes a `DeviceDescription`: a stable identifier for the browser or server (store a random one in the PHP
session or a cookie), and the platform, `web` by default.

```php
use AudienceKit\DeviceDescription;

$_SESSION['device'] ??= bin2hex(random_bytes(16));
$device = new DeviceDescription($_SESSION['device']);
```

After a sign-in succeeds, call `session_regenerate_id(true)` so the session ID that carried the person's credential is
new.

## Facebook

Open Facebook's login dialog (for Facebook Login for Business, with the configuration ID the audience's branding gives
as `facebook_login_config_id`), and when Facebook redirects back with a `code`, trade it. The redirect URI must be
exactly the one the dialog was opened with:

```php
$branding = $audienceKit->branding();     // public: the audience, its theme and its login configuration

// 1. Send the person to Facebook.
$state = bin2hex(random_bytes(16));
$_SESSION['oauth_state'] = $state;
$redirect = 'https://example.com/auth/facebook';
header('Location: https://www.facebook.com/v21.0/dialog/oauth?' . http_build_query([
    'client_id' => '123456789',
    'redirect_uri' => $redirect,
    'state' => $state,
    'config_id' => $branding['facebook_login_config_id'] ?? null,
    'response_type' => 'code',
]));

// 2. On https://example.com/auth/facebook:
if (!hash_equals($_SESSION['oauth_state'] ?? '', $_GET['state'] ?? '')) {
    http_response_code(400);
    exit;
}
$audienceKit->signInWithFacebookCode($_GET['code'], $redirect, $device);
session_regenerate_id(true);
```

The API trades the code with the app secret, so the secret never reaches your server. When the dialog belongs to
another Facebook app than the configured one, pass its ID as the fourth argument. A Facebook user access token the
browser got from the JavaScript SDK works too: `signInWithFacebookToken($accessToken, $device)`.

## Google

Google Identity Services posts an ID token (its `credential`) to your login endpoint. Check its CSRF cookie, then
trade it:

```php
if (($_POST['g_csrf_token'] ?? '') === '' || !hash_equals($_COOKIE['g_csrf_token'] ?? '', $_POST['g_csrf_token'])) {
    http_response_code(400);
    exit;
}
$audienceKit->signInWithGoogle($_POST['credential'], $device);
```

The ID token carries only the account's primary email. To let the API match an existing account by the Google
account's other verified emails, also ask for the `https://www.googleapis.com/auth/user.emails.read` scope and pass
the access token: `signInWithGoogle($idToken, $device, accessToken: $accessToken)`. A person already signed in can add
Google to their account with `connectGoogle($idToken, $device)`.

## Sign in with Apple

Sign in with Apple JS returns an identity token, an authorization code and, the first time only, the person's name.
Pass them with the redirect URI and the nonce you gave Apple:

```php
$audienceKit->signInWithApple(
    identityToken: $response['authorization']['id_token'],
    device: $device,
    authorizationCode: $response['authorization']['code'],
    redirectUri: 'https://example.com/auth/apple',
    nonce: $_SESSION['apple_nonce'],
    firstName: $response['user']['name']['firstName'] ?? null,
    lastName: $response['user']['name']['lastName'] ?? null,
);
```

## App Review codes

While an audience is in App Review, its console issues a code a reviewer types instead of signing in with a provider:

```php
$audienceKit->signInWithReviewCode($_POST['code'], $device);
```

A wrong or expired code throws `AudienceKitException` with `SIGN_IN_REJECTED`.

## When sessions end

A session ends when the person signs out, when an admin ends it, or when it expires. When the API refuses it, the call
throws `AudienceKitException` with `UNAUTHENTICATED` and the SDK forgets the credential, so `isSignedIn()` turns
false: send the person back to sign in.

```php
use AudienceKit\AudienceKitException;

try {
    $admissions = $audienceKit->admissions();
} catch (AudienceKitException $error) {
    if ($error->isUnauthenticated()) {
        header('Location: /sign-in');
        exit;
    }
    throw $error;
}
```

`refreshSession()` re-issues the token for the same session (after the API rotates its signing key, say).
`signOut()` forgets the credential and revokes the token everywhere.

## Deleting an account

App stores and privacy law expect people to be able to delete their account from wherever they signed up. After the
person confirms:

```php
if ($audienceKit->deleteAccount()) {
    session_destroy();
}
```

It erases their data in the audience and signs them out everywhere, and can't be undone.

## Keeping the credential somewhere else

`SessionCredentialStore` keeps the credential in `$_SESSION`. For a framework's session, a database row or an
encrypted cookie, implement `CredentialStore`'s three methods (`load()`, `save()`, `delete()`) with
`Credential::fromArray()` and `toArray()`. The token is as good as a password: keep it server-side or encrypted, and
never log it.
