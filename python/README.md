# AudienceKit for Python

The `audiencekit` package: an audience's venues, people, locales, events and the signed-in person's own state, over
the AudienceKit GraphQL API (`https://api.audiencekit.com/v1/audience/<audience id>/graphql`). Python 3.10 or newer,
on [httpx](https://www.python-httpx.org), with a blocking `Client` and an asyncio `AsyncClient` that take the same
calls. Typed throughout (`py.typed`).

It carries the same documents and models as the Swift and Kotlin SDKs in this repository, so an app or a service built
with it reads the API the way the apps do, with the same tolerance for audiences that haven't installed a module.

- [Building a website](docs/websites.md): service tokens, the public listings, the community, news and caching.
- [Signing people in](docs/sign-in.md): Facebook, Google, Apple and App Review codes, one session per browser.
- [Reference](docs/reference.md): every call, model and helper.
- [Examples](examples/README.md): a listings page, a news digest, Facebook sign-in, member actions and a community
  export, each a program you can run.

## Installation

```sh
pip install audiencekit
```

Or, from this repository: `pip install ./python`.

## Usage

```python
from audiencekit import Client, Configuration, Credential, DeviceDescription

client = Client(Configuration(host="hotmess.social"))

# Either sign a person in with a Facebook (or Apple) token the app obtained…
credential = client.sign_in_with_facebook(facebook_access_token, DeviceDescription("install-id"))
# …or adopt a credential minted elsewhere (a service token from the console, or one you saved):
client.adopt(Credential.from_json(saved_json))

for event in client.events():  # soonest first; window="PAST" for the latest
    print(event.name, event.start_at, event.venue_name, event.rsvp and event.rsvp.count)

venues = client.venues()
people = client.people()
me = client.me()
client.rsvp_event(event.id, "ATTENDING")
```

The same calls on asyncio:

```python
async with AsyncClient(Configuration(host="hotmess.social"), credential=credential) as client:
    venues = await client.venues()
```

### Servers and jobs: service tokens

A server that reads as the audience, with no one signed in, uses a service token from the audience's console:

```python
client = Client.from_environment()  # AUDIENCEKIT_TOKEN=akst_…, AUDIENCEKIT_HOST=hotmess.social

for listing in client.public_listings():  # needs the public:read scope
    print(listing.kind, listing.title)

community = client.community()  # the audience, locales, venues, people, events and series
```

The client trades the token for an hour-long session and renews it before it runs out. See
[Building a website](docs/websites.md).

### News, cover, chat and the calendar

Audiences with Soapbox carry news (`articles()`, `article(id)`, `articles_about("venue", id)`, `publications()`); a
signed-in member can buy cover (`venue_cover()`, `buy_cover()`, `cover_pass_code()` for the door), chat
(`send_chat_message()`), add events to their calendar (`create_calendar_feed()`) and report or block
(`report_content()`, `block_user()`). Every call is in the [reference](docs/reference.md).

### Your own operations

`client.graphql(query, variables, operation_name)` runs any document against the audience's endpoint and returns its
`data`; `client.run(Operation(...))` adds the module-tolerant retry below to one of your own. Both take an `endpoint`
for packages built for other views of the API (`"graphql"`, the consumer view, by default).

### Modules the audience doesn't have

The API leaves a module's fields out of an audience that hasn't installed it (Facebook Pages, Google Places, RSVP,
Ticketing, Friends…), and asking for one fails the whole operation with `undefinedField`. The typed calls first ask for
everything; when the API refuses a field they ask the schema which fields the operation's types have, cache the answer
for the session, and run the operation again with only those. The models' module fields (`Event.rsvp`, `Venue.page`,
`Person.home_venue`…) are `None` when the audience doesn't have them.

### Errors

Every failure raises `AudienceKitError`, with a `code` from the API's vocabulary (`UNAUTHENTICATED`, `FORBIDDEN`,
`NOT_FOUND`, `INVALID` with per-field messages in `fields`, `RATE_LIMITED`, `CONFLICT`, `INTERNAL`) or the SDK's own
(`NOT_SIGNED_IN`, `SIGN_IN_REJECTED`, `NETWORK`, `DECODING`, `MISSING_CONFIGURATION`, `UPDATE_REQUIRED`…), the
message, the HTTP `status` when there was one, and the GraphQL `errors` when the operation returned any. When the API
rejects the session (HTTP 401), the client forgets the credential and tells your `on_session_change` listener
`session_ended`; sign in again.

### Headers

Every call carries `Authorization: Bearer <token>`, `X-AudienceKit-API-Version` (the contract date this SDK speaks),
`X-AudienceKit-Client: AudienceKit-Python/<version>` and, for staging builds (`Configuration(environment="staging")`),
`X-AudienceKit-Environment: staging`.

## Development

```sh
cd python
python -m venv .venv && . .venv/bin/activate
pip install -e ".[dev]"
pytest --cov          # fails under 85% line coverage, the repository's floor
ruff check . && ruff format --check . && mypy
```

The tests run against a fake API behind `httpx.MockTransport` (`tests/conftest.py`), which records every request the
client sends and answers each GraphQL operation by name.

## Versioning and releases

The package keeps its own version in [`src/audiencekit/_version.py`](src/audiencekit/_version.py), separate from the
Swift and Kotlin SDKs' `VERSION` at the repository root, and the root `release` job doesn't publish it. Add the
version's entry to [`CHANGELOG.md`](CHANGELOG.md). Once a change that raises the version merges to `main`, the
`python-release` workflow builds the sdist and wheel, uploads them to PyPI with
[trusted publishing](https://docs.pypi.org/trusted-publishers/) (PyPI's publisher names `lwm-luminx/audience-kit-sdk`,
workflow `python-release.yml`, environment `pypi`), and tags the commit `python-<version>` (the prefix keeps it apart
from the Swift package's bare version tags, which Swift Package Manager resolves).

## License

Source-available under the [AudienceKit SDK License](../LICENSE) 1.2 (`LicenseRef-AudienceKit-SDK-1.2`), © Love Wins
Media, Inc.: use it only in apps that connect to AudienceKit as hosted by Love Wins Media. Every other use is
prohibited without Love Wins Media's written permission and an audience ID or token issued for that use. No other
license is granted, misrepresenting the work is prohibited, and changed versions may be made only in a fork after
written notice. See the
[root README](../README.md#license) for details.
