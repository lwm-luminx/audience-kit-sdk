# AudienceKit for PHP

A PHP 8.1+ client for the [AudienceKit](https://audiencekit.com) consumer GraphQL API
(`https://api.audiencekit.com/v1/audience/<audience-id>/graphql`): sign a person in, then read the audience's venues,
people, locales, events, chat and cover charges with the same calls the Swift and Kotlin SDKs make, so an app is built
with little custom code. Part of the [AudienceKit SDK](../README.md) repository, versioned on its own.

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

## Usage

```php
use AudienceKit\AudienceSession;
use AudienceKit\Configuration;
use AudienceKit\Credential;
use AudienceKit\DeviceDescription;

$session = new AudienceSession(new Configuration(
    host: 'hotmess.social',   // names the audience; or audienceId: '<uuid>'
    facebookAppId: '123',     // the Facebook app your sign-in uses
));

// Sign in with a Facebook user access token (or an OAuth code, or an Apple identity token)...
$credential = $session->signInWithFacebookToken($facebookToken, new DeviceDescription('server-1'));

// ...or adopt a credential minted elsewhere (a service token, a venue device's, one you stored).
$session->adopt(Credential::fromArray($storedJson));

$venues = $session->venues();            // list<array>: id, name, locale, location { point address }, tags…
$events = $session->events('UPCOMING');  // soonest first; 'PAST' for what has ended
$venue = $session->venueDetail($venues[0]['id']);
$session->rsvpEvent($events[0]['id'], 'ATTENDING');
$session->sendChatMessage('Hello from PHP', ['venueId' => $venues[0]['id']]);

// Any operation of your own, decoded to arrays:
$data = $session->graphQL('query Me { me { self { id name } } }');
```

Results are the API's JSON as arrays, keyed as the schema names them, with dates as ISO 8601 strings. Fields a module
adds (Facebook Pages, Google Places, RSVP, People, Ticketing, Friends, Chat) are missing where the audience hasn't
installed that module: the SDK asks for them and, if the audience's schema doesn't have one, asks the schema which
fields it has and runs the query again with only those (cached for the session).

Every call carries `X-AudienceKit-Client`, `X-AudienceKit-API-Version` and, for staging builds,
`X-AudienceKit-Environment`. Requests go to the API instance the credential's `endpoint` names, so a credential
issued by the next preview talks to the next preview.

### Errors

Every failure is an `AudienceKit\AudienceKitException`. Its `errorCode` is one of the API's codes
(`UNAUTHENTICATED`, `FORBIDDEN`, `NOT_FOUND`, `INVALID` with per-field messages in `fields`, `RATE_LIMITED`,
`CONFLICT`, `INTERNAL`) or the SDK's own (`NOT_SIGNED_IN`, `SIGN_IN_REJECTED`, `NETWORK`, `DECODING`,
`UPDATE_REQUIRED`…), all constants on the class. A 401 forgets the stored credential, so check `isSignedIn()` and
sign in again.

### Keeping the session

Pass a `CredentialStore` to keep the credential wherever your app keeps secrets (a server-side session, an encrypted
cookie); the default `InMemoryCredentialStore` lives as long as the object. The token is as good as a password: never
log it. `Credential::toArray()` and `Credential::fromArray()` round-trip the API's JSON.

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
`Queries.swift` builds them; keep them in step when the shared queries change.

## Releasing

The version is `AudienceKit::VERSION` in `src/AudienceKit.php`, with an entry in [`CHANGELOG.md`](CHANGELOG.md).
A change to `php/` takes a new one; CI checks (`scripts/check-version.sh`). Once it merges to `main`, the `php` job
tags the commit `php/<version>`, a tag with a prefix so it never clashes with the Swift package's bare `X.Y.Z` tags,
which Swift Package Manager resolves from.

Composer can't install a package from a subdirectory of a repository, so publishing to Packagist goes through a
read-only split of `php/`, the way other monorepos publish (`git subtree split --prefix=php`), pushed with the bare
`X.Y.Z` tag to its own repository, which Packagist tracks. Until that repository exists, install from the split or a
path repository.

## License

See the repository's [LICENSE](../LICENSE).
