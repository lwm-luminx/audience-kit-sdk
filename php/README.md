# AudienceKit for PHP

A PHP 8.1+ client for the [AudienceKit](https://audiencekit.com) API, for websites, WordPress plugins, backends and
scripts: sign a person in (or use an audience's service token), then read the audience's venues, people, locales,
events, news, chat and cover charges with the same calls the Swift, Kotlin, Node and Python SDKs make, so a site is
built with little custom code. Part of the [AudienceKit SDK](../README.md) repository, versioned on its own.

## Installation

```sh
composer require audiencekit/audiencekit
```

HTTP goes through any [PSR-18](https://www.php-fig.org/psr/psr-18/) client with
[PSR-17](https://www.php-fig.org/psr/psr-17/) factories. When you don't pass one, `php-http/discovery` finds what's
installed, so add a client if your project has none:

```sh
composer require guzzlehttp/guzzle
```

Until the package is on Packagist, point Composer at the split repository (see [Releasing](#releasing)).

## Quick start

A website that lists an audience's venues and events needs no sign-in, only a service token an admin minted in the
audience's console with the `public:read` scope (or `AUDIENCEKIT_TOKEN` in the environment):

```php
use AudienceKit\AudienceSession;

$session = AudienceSession::fromEnvironment();      // AUDIENCEKIT_TOKEN=akst_…, AUDIENCEKIT_HOST=hotmess.social

foreach ($session->events() as $event) {            // upcoming, soonest first
    printf("%s at %s, %s\n", $event->name, $event->venueName ?? 'TBA', $event->startAt?->format('D g:ia'));
}
```

An app that acts for a person signs them in first:

```php
use AudienceKit\AudienceSession;
use AudienceKit\Configuration;
use AudienceKit\DeviceDescription;

$session = new AudienceSession(new Configuration(
    host: 'hotmess.social',   // names the audience; or audienceId: '<uuid>'
    facebookAppId: '123',     // the Facebook app your sign-in uses
));

// Facebook (a token or an OAuth code), Google, Sign in with Apple, or an App Review code...
$session->signInWithFacebookCode($_GET['code'], 'https://example.com/callback', new DeviceDescription('web-1'));

$venues = $session->venues();                       // list<Venue>
$venue = $session->venueDetail($venues[0]->id);     // with its profile, chat and upcoming events
$events = $session->events('UPCOMING', venueId: $venue->id);
$session->rsvpEvent($events[0]->id, 'ATTENDING');
$session->sendChatMessage('Hello from PHP', ['venueId' => $venue->id]);

// Any operation of your own, decoded to arrays:
$data = $session->graphQL('query Me { me { self { id name } } }');
```

Read on:

- [Signing people in](docs/sign-in.md) on a website: Facebook, Google, Apple, App Review codes, keeping the session in
  PHP's session, signing out and deleting an account.
- [Building a website](docs/websites.md) from an audience: service tokens, public listings, the community in one call,
  Soapbox news, calendar subscriptions, cover passes and caching.
- [Reference](docs/reference.md): every call, model and helper.

## What you get back

Every call returns a model from `AudienceKit\Model` (`Venue`, `Event`, `Person`, `Locale`, `Admission`, `Article`…)
with typed, read-only properties: dates are `DateTimeImmutable`, money is `Money` (`$charge->total?->format()`),
points are `Coordinate`. A model is also readable as the API's JSON, so `$venue['locale']['name']` works and fields
the model has no property for are still there; `raw()` and `json_encode()` give you that array.

Fields a module adds (Facebook Pages, Google Places, RSVP, People, Ticketing, Friends, Chat, Soapbox) are missing
where the audience hasn't installed that module: the SDK asks for them and, if the audience's schema doesn't have
one, asks the schema which fields it has and runs the query again with only those (cached for the session). The
matching properties are null or empty.

Every call carries `X-AudienceKit-Client`, `X-AudienceKit-API-Version` and, for staging builds,
`X-AudienceKit-Environment`. Requests go to the API instance the credential's `endpoint` names, so a credential
issued by the next preview talks to the next preview.

### Errors

Every failure is an `AudienceKit\AudienceKitException`. Its `errorCode` is one of the API's codes
(`UNAUTHENTICATED`, `FORBIDDEN`, `NOT_FOUND`, `INVALID` with per-field messages in `fields`, `RATE_LIMITED`,
`CONFLICT`, `INTERNAL`) or the SDK's own (`NOT_SIGNED_IN`, `SIGN_IN_REJECTED`, `NETWORK`, `DECODING`,
`UPDATE_REQUIRED`…), all constants on the class. A 401 forgets the stored credential, so check `isSignedIn()` and
sign in again; a service token's session is traded again once before that.

### Keeping the session

Pass a `CredentialStore` to keep the credential wherever your app keeps secrets (a server-side session, an encrypted
cookie); the default `InMemoryCredentialStore` lives as long as the object. The token is as good as a password: never
log it (`var_dump()` of a `Credential` leaves it out). `Credential::toArray()` and `Credential::fromArray()`
round-trip the API's JSON.

### Upgrading from 0.1

0.1 returned arrays; 0.2 returns models that read the same way, so `$venue['name']` keeps working. Code that checks
`is_array()` on a result, or passes one to a function typed `array`, needs `instanceof` or `->raw()`. `tribes()`
returns `Tag` and `TribeIdentification` models under the same keys.

## Development

```sh
cd php
composer install
composer test                 # PHPUnit
composer coverage             # with the 85% line-coverage floor CI enforces (needs Xdebug or PCOV)
composer graphql-documents    # writes every document to build/graphql for the schema check (graphql@16 installed at the repo root):
node ../scripts/graphql/check.mjs --schema ../graphql/schema.graphql --endpoint consumer build/graphql
```

The GraphQL documents live in `src/Queries.php`, built from the audience's `SchemaShape` the way the Swift SDK's
`Queries.swift` builds them; keep them in step when the shared queries change. The models are in `src/Model/`; each
reads only what the documents ask for, and keeps the rest in `raw()`.

## Releasing

The version is `AudienceKit::VERSION` in `src/AudienceKit.php`, with an entry in [`CHANGELOG.md`](CHANGELOG.md).
A change to `php/` takes a new one; CI checks (`scripts/check-version.sh`). Once it merges to `main`, the `php` job
tags the commit `php/<version>`, a tag with a prefix so it never clashes with the Swift package's bare `X.Y.Z` tags,
which Swift Package Manager resolves from.

Composer can't install a package from a subdirectory of a repository, so publishing to Packagist goes through a
read-only mirror of `php/`: the `split` job in `.github/workflows/php.yml` copies `php/` (with the repository's
`LICENSE`) to [lwm-luminx/audiencekit-php](https://github.com/lwm-luminx/audiencekit-php) and tags it with the bare
`X.Y.Z` version, which Packagist picks up. Make changes here, never in the mirror.

## License

Source-available under the [AudienceKit SDK License](../LICENSE) 1.2 (`LicenseRef-AudienceKit-SDK-1.2`), © Love Wins
Media, Inc.: use it only in apps that connect to AudienceKit as hosted by Love Wins Media. Every other use is
prohibited without Love Wins Media's written permission and an audience ID or token issued for that use. No other
license is granted, misrepresenting the work is prohibited, and changed versions may be made only in a fork after
written notice. See the
[root README](../README.md#license) for details.
