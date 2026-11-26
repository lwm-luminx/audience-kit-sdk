# AudienceKit for Ruby

A Ruby 3.2+ client for the [AudienceKit](https://audiencekit.com) API, for Rails and Sinatra sites, jobs, bots and
scripts: sign a person in (or use an audience's API key or service token), then read the audience's venues, people,
locales, events, news, chat and cover charges with the same calls the Swift, Kotlin, Node, Python and PHP SDKs make, so
a site is built with little custom code. Part of the [AudienceKit SDK](../README.md) repository, versioned on its own.

## Installation

```ruby
# Gemfile
gem "audience-kit", "~> 0.3"
```

```sh
bundle install
```

Or `gem install audience-kit`. The only dependency is [Faraday](https://lostisland.github.io/faraday/) 2.x, so the
gem works with whatever adapter your app already uses.

## Quick start

A script or job that reads an audience needs no sign-in, only a token an admin made in the audience's console: an
application API key for the GraphQL reads, or a service token (`akst_...`) with `public:read` for the public
listings. Put it in the environment:

```sh
export AUDIENCEKIT_TOKEN=...              # never commit it
export AUDIENCEKIT_HOST=hotmess.social    # names the audience; or AUDIENCEKIT_AUDIENCE_ID=<uuid>
```

```ruby
require "audience-kit"

session = Audience::Kit::Session.from_env

session.events.each do |event|            # upcoming, soonest first
  puts "#{event.start_at&.strftime("%a %-l:%M%P")}  #{event.name} at #{event.venue_name || "TBA"}"
end
```

A site that acts for a person signs them in first:

```ruby
session = Audience::Kit::Session.new(
  configuration: Audience::Kit::Configuration.new(
    host: "hotmess.social",                # names the audience; or audience_id: "<uuid>"
    facebook_app_id: "123456789"           # the Facebook app your login dialog uses
  ),
  store: Audience::Kit::SessionCredentialStore.new(session_hash)   # Rails' session, Rack's, Sinatra's
)
device = Audience::Kit::DeviceDescription.new(identifier: browser_id)

# Facebook (a token or an OAuth code), Google, Sign in with Apple, or an App Review code...
session.sign_in_with_facebook_code(params[:code], redirect_uri: callback_url, device: device)

venue = session.venue_detail(session.venues.first.id)  # with its profile, chat and upcoming events
event = session.events(venue_id: venue.id).first
session.rsvp_event(event.id, "ATTENDING")
session.send_chat_message("Hello from Ruby", venue_id: venue.id)

# Any operation of your own:
session.graphql("query Me { me { self { id name } } }")
```

Read on:

- [Signing people in](docs/sign-in.md) on a Rails or Sinatra site: Facebook, Google, Apple, App Review codes, keeping
  the session in the framework's session, signing out and deleting an account.
- [Building a website](docs/websites.md) from an audience: API keys and service tokens, public listings, the community
  in one call, Soapbox news, calendar subscriptions, cover passes and caching.
- [Reference](docs/reference.md): every call, model and helper. The YARD reference is on
  [RubyDoc.info](https://rubydoc.info/gems/audience-kit), and `bundle exec rake yard` builds it locally.
- [Examples](examples/README.md): runnable programs for a listings page, a news digest, member actions and a
  community export.

## What you get back

Every call returns a model (`Audience::Kit::Venue`, `Event`, `Person`, `Locale`, `Admission`, `Article`...) with
snake_case readers: times are `Time`, money is `Money` (`charge.total&.format # => "$12.00"`), points are
`Coordinate`, and yes-or-no fields end in `?` (`event.canceled?`, `venue.hidden?`). A model is also readable as the
API's JSON, so `venue["locale"]["name"]` works and fields the model has no reader for are still there; `to_h` and
`to_json` give you that Hash. Models are read-only.

Fields a module adds (Facebook Pages, Google Places, RSVP, People, Ticketing, Friends, Chat, Soapbox) are missing
where the audience hasn't installed that module: the SDK asks for them and, if the audience's schema doesn't have
one, asks the schema which fields it has and runs the query again with only those (cached for the session). The
matching readers return nil or an empty Array.

Every call carries `X-AudienceKit-Client`, `X-AudienceKit-API-Version` and, for staging builds,
`X-AudienceKit-Environment`. Requests go to the API instance the credential's `endpoint` names, so a credential
issued by the preview API talks to the preview API.

### Errors

Every failure is an `Audience::Kit::Error`. Its `code` is one of the API's (`UNAUTHENTICATED`, `FORBIDDEN`,
`NOT_FOUND`, `INVALID` with per-field messages in `fields`, `RATE_LIMITED`, `CONFLICT`, `INTERNAL`) or the SDK's own
(`NOT_SIGNED_IN`, `SIGN_IN_REJECTED`, `NETWORK`, `DECODING`, `UPDATE_REQUIRED`...), all constants on the class.
When the API refuses a person's session, the SDK forgets the credential, so check `signed_in?` and sign in again; a
service token's session is traded again once before that.

```ruby
begin
  session.rsvp_event(event_id, "ATTENDING")
rescue Audience::Kit::Error => e
  return redirect_to(sign_in_path) if e.unauthenticated?

  flash[:alert] = e.message   # written for people
end
```

### Keeping the session

Pass a `store:` to keep the credential wherever your app keeps secrets. `SessionCredentialStore` keeps it in a Rails,
Rack or Sinatra session; the default `MemoryCredentialStore` lives as long as the object. Any object with `load`,
`save(credential)` and `delete` works. The token is as good as a password: never log it (`Credential#inspect` leaves
it out). `Credential#to_h` and `Credential.from_h` round-trip the API's JSON.

### The module-level session

Scripts that talk to one audience can skip making a session:

```ruby
Audience::Kit.configure do |c|
  c.token = ENV.fetch("AUDIENCEKIT_TOKEN")
  c.host = "hotmess.social"
end

Audience::Kit.session.venues
Audience::Kit::Venue.find(venue_id)          # a venue's page; raises NOT_FOUND when there's none
Audience::Kit::Event.find(event_id)
Audience::Kit.query("query { locales { id name } }")
```

Without `configure`, it reads `AUDIENCEKIT_TOKEN`, `AUDIENCEKIT_HOST`, `AUDIENCEKIT_AUDIENCE_ID`,
`AUDIENCEKIT_BASE_URL` and `AUDIENCEKIT_ENVIRONMENT` (and the 0.2 releases' `AUDIENCE_KIT_*` names).

### Upgrading from 0.2

0.2 read two REST endpoints the API no longer serves, so every 0.2 call fails; upgrade. In 0.3,
`Venue.find` and `Event.find` read over GraphQL with the module-level session, so set a host or audience ID as well as
the token. `data` still returns the record's JSON, now with the schema's camelCase keys, and typed readers sit beside
it. The default API is `https://api.audiencekit.com`.

## Related Ruby gems

Two open-source (MIT) gems from the team behind AudienceKit, for the server side of a Rails app on PostgreSQL. They
don't talk to the AudienceKit API; reach for them when your app keeps listings of its own (a city guide that mirrors
an audience's venues and events into its database, say):

- [**graph_query**](https://github.com/lwm-luminx/graph_query) ([guide](https://lwm-luminx.github.io/graph_query/)):
  graph traversals and Cypher queries over Active Record, in one recursive CTE with no database extension. Walk
  locales within locales to their venues and events (`washington.traverse(:contains, depth: 0..).traverse(:has_venue)`)
  and get relations back.
- [**retcon**](https://github.com/lwm-luminx/retcon) ([guide](https://lwm-luminx.github.io/retcon/)): retroactive
  continuity for Active Record. Field-level history with attribution, proposals reviewed like pull requests, and
  repair of bad edits without losing the good work after them, for records many people edit.

## Development

```sh
cd ruby
bin/setup
bundle exec rake               # specs (every line and branch of lib/ covered) and RuboCop
bundle exec rake yard          # the API reference, in doc/
bin/console                    # a prompt with the gem loaded
bin/graphql-documents build/graphql   # every document, for the schema check (graphql@16 installed at the repo root):
node ../scripts/graphql/check.mjs --schema ../graphql/schema.graphql --endpoint consumer build/graphql
```

The GraphQL documents live in `lib/audience-kit/queries.rb`, built from the audience's `SchemaShape` the way the
other SDKs build theirs; keep them in step when the shared queries change. The models are in
`lib/audience-kit/models.rb`; each reads only what the documents ask for, and keeps the rest in `to_h`. Signatures
for the public API are in `sig/`.

## Releasing

The gem keeps its own version in `lib/audience-kit/version.rb`, separate from the Swift and Kotlin SDKs' `VERSION`.
Releases publish themselves: once a change that raises the version (with a [`CHANGELOG.md`](CHANGELOG.md) entry)
merges to `main`, the `release` job in `.github/workflows/ruby.yml` builds the gem and pushes it to
[rubygems.org](https://rubygems.org/gems/audience-kit) with RubyGems trusted publishing (no API key is stored), then
tags the commit `ruby-<version>`. Don't use `bundle exec rake release`, which would push a bare version tag that the
Swift package's release tags share.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/lwm-luminx/audience-kit-sdk (the gem lives
in `ruby/`). This project is intended to be a safe, welcoming space for collaboration, and contributors are expected
to adhere to the [code of conduct](https://github.com/lwm-luminx/audience-kit-sdk/blob/main/ruby/CODE_OF_CONDUCT.md).

## License

Source-available under the [AudienceKit SDK License](LICENSE) 1.2 (`LicenseRef-AudienceKit-SDK-1.2`), © Love Wins
Media, Inc.: use it only in apps that connect to AudienceKit as hosted by Love Wins Media. Every other use is
prohibited without Love Wins Media's written permission and an audience ID or token issued for that use. No other
license is granted, misrepresenting the work is prohibited, and changed versions may be made only in a fork after
written notice. See the
[root README](../README.md#license) for details.
