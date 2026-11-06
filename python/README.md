# AudienceKit for Python

The `audiencekit` package: an audience's venues, people, locales, events and the signed-in person's own state, over
the AudienceKit GraphQL API (`https://api.audiencekit.com/v1/audience/<audience id>/graphql`). Python 3.10 or newer,
on [httpx](https://www.python-httpx.org), with a blocking `Client` and an asyncio `AsyncClient` that take the same
calls. Typed throughout (`py.typed`).

It carries the same documents and models as the Swift and Kotlin SDKs in this repository, so an app or a service built
with it reads the API the way the apps do, with the same tolerance for audiences that haven't installed a module.

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
version's entry to [`CHANGELOG.md`](CHANGELOG.md). To publish, push a tag of the form `python-0.1.0` (the `python-`
prefix keeps it apart from the Swift package's bare `0.42.0` tags, which Swift Package Manager resolves): the
`python-release` workflow builds the sdist and wheel from that tag, checks the tag matches the version, and uploads
them to PyPI with [trusted publishing](https://docs.pypi.org/trusted-publishers/) (set the `pypi` environment up once
on PyPI for `lwm-luminx/audience-kit-sdk`, workflow `python-release.yml`). Or by hand: `python -m build` then
`twine upload dist/*`.

## License

The [AudienceKit SDK License](../LICENSE) at the root of the repository: use it freely, with the AudienceKit service
Love Wins Media operates only.
