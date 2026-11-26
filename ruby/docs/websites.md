# Building a website with Ruby

A venue's site, a city guide, a Discord bot or a newsletter job can be built from what an audience lists, with the
same calls the apps make. This page covers reading as the audience (no one signed in), the public listings, Soapbox
news, and what a signed-in visitor can do on a site.

## Read as the audience: API keys and service tokens

An admin makes tokens in the audience's console. Keep them in the environment or Rails credentials, never in the
repository:

```sh
AUDIENCEKIT_TOKEN=...
AUDIENCEKIT_HOST=hotmess.social
```

```ruby
session = Audience::Kit::Session.from_env
```

`from_env` also reads `AUDIENCEKIT_BASE_URL`, `AUDIENCEKIT_AUDIENCE_ID` and `AUDIENCEKIT_ENVIRONMENT` (`staging` for a
staging build), and takes `http:`, a Faraday connection of your own (for timeouts, instrumentation or a proxy). With a
token from somewhere else:

```ruby
session = Audience::Kit::Session.new(configuration: Audience::Kit::Configuration.new(host: "hotmess.social"))
session.use_bearer_token(Rails.application.credentials.audiencekit_api_key)
```

Which token to use:

- **An application API key** reads everything below the public listings: `community`, `events`, `venues`, news and
  the rest. Anything in `AUDIENCEKIT_TOKEN` that doesn't start `akst_` is sent as is, or pass it to
  `use_bearer_token`.
- **A service token** (`akst_<prefix>_<secret>`) with the `public:read` scope reads the public listings. The session
  trades it at `POST /v1/token/service` for an hour-long session, trades it again a minute before that runs out, and
  once more if the API refuses the session (after a key rotation, say). A token an admin revoked raises
  `Audience::Kit::Error` with `UNAUTHENTICATED`. The GraphQL reads refuse a service session for now, so a site that
  renders from them uses an application API key.

Keep both on the server.

## The public listings

What the audience shows anyone, as its own websites show it: up to 500 venues, then events, then posts, a page at a
time. Plain text, ready for a template:

```ruby
listings = session.public_listings.select(&:public?)   # "community" listings show in full only to members

listings.group_by(&:kind).each do |kind, items|
  puts "## #{kind.capitalize}s"
  items.each do |listing|
    case listing.kind
    when "venue" then puts "#{listing.title}, #{listing.address}"
    when "event" then puts "#{listing.start_at&.strftime("%b %-d")}: #{listing.title} at #{listing.venue_name}"
    when "post" then puts "#{listing.title}: #{listing.description}"
    end
  end
end
```

`public_listings_page(page)` reads one page (with `next_page` for the next), `public_listing(:venue, id)` one listing
(nil when it's gone), and `public_tonight(venue_id)` what a screen facing the room shows: tonight's event, who's on and
what's next. [`examples/listings_page.rb`](../examples/listings_page.rb) writes a static page of listings.

## The community in one call

For a site that renders from the richer GraphQL models (venues with their locales, points and tags; events with their
venues, hosts and tickets), `community` reads the audience, its locales, venues, people, upcoming events and event
series together. A part whose module the audience doesn't have comes back empty.

```ruby
community = session.community

community.venues.each do |venue|
  point = venue.coordinate                            # Audience::Kit::Coordinate, for a map
  tags = venue.tags.map(&:name)
end

accent = community.audience&.color("accent")          # Audience::Kit::Color from the audience's theme
accent&.to_css                                        # "rgba(255, 51, 102, 1)"
```

The individual calls are there too: `venues`, `people`, `locales`, `events(window:, locale_id:, venue_id:)`,
`event_series`, `event(id)`, `venue_detail(id)` and `closest_locale(coordinate)`.
[`examples/community_export.rb`](../examples/community_export.rb) writes the whole community as JSON for a static site
generator (Jekyll's `_data/`, Bridgetown, Middleman).

Event times are `Time` in UTC; show them in the locale's zone with `event.start_at.in_time_zone("America/Phoenix")`
in Rails, or `getlocal` elsewhere. `event.ended?` says whether it is over, and `event.effective_hosts` who runs the
night: its hosts or, when nobody else is linked to it, its KJ, DJ or VJ.

## News

Audiences with Soapbox carry local news and op-eds from publications they trust:

```ruby
# The latest, pinned first, for a locale (or one publication).
session.articles(locale_id: locale.id, first: 10).each do |article|
  puts "#{article.title} (#{article.publication&.name})"
end

# "Show more": page through with the cursor.
page = session.articles_page(locale_id: locale.id, after: params[:after])
link_to "Show more", news_path(after: page.end_cursor) if page.next_page?

# One article, with its Markdown body and what it is about.
article = session.article(id)
```

Also `national_articles`, `articles_about(:venue | :event | :person | :locale, id)` for "In the news" on a listing's
page, `publications`, `local_publications(locale_id)` and `publication(id)`. Show `article.disclosure` when there is
one, and link `article.canonical_url` when `article.teaser?`: the rest of the article is on the publication's site. A
signed-in reader can send a publication that accepts them (`publication.accepts_op_eds?`) an op-ed with
`submit_op_ed`, and follow it with `my_op_eds`. [`examples/news_digest.rb`](../examples/news_digest.rb) writes a
Markdown digest for a newsletter.

Every Soapbox call returns nothing, rather than failing, for an audience without Soapbox.

## Things a signed-in visitor can do

Once someone has [signed in](sign-in.md), a site can do what the apps do
([`examples/member_actions.rb`](../examples/member_actions.rb) walks through them):

- RSVP: `rsvp_event(event_id, "ATTENDING")`, `cancel_rsvp(event_id)` and `event_rsvp(event_id)` for who's going.
- Calendar: `create_calendar_feed` returns links (`feed.url`, `webcal_url`, `google_url`) that add every event they're
  going to to their own calendar, and `follow_venue_in_calendar(venue_id)` adds every event at a venue.
- Cover: `venue_cover(venue_id)` says tonight's charge; `buy_cover(venue_id)` (with `amount_cents:` on a sliding
  scale) or `buy_coat_check(venue_id, quantity:)` starts paying with the venue's provider. For Stripe, confirm
  `payment_intent_client_secret` with Stripe.js and call `confirm_cover`; for Square, tokenize with the Web Payments
  SDK and call `pay_cover`. `admission.pass_code` is the code to show at the door as a QR code; it changes every 30
  seconds, so render it in the page and refresh it, rather than caching it.
- Chat: `send_chat_message(text, venue_id:)`, `remove_chat_message`, and `report_content`, `block_user` and
  `unblock_user` so people can report what they see. Offer `Audience::Kit::ReportTarget::REASONS` as the reasons.
- Tribes and notifications: `tribes`, `identify_with_tribe`, `leave_tribe` and `register_device`.

## Caching

Listings change a few times a day, so cache what the page renders, not the session. Cache the JSON and rebuild models
when reading:

```ruby
events = Rails.cache.fetch("audiencekit/events", expires_in: 5.minutes) do
  session.events.map(&:to_h)
end.map { |json| Audience::Kit::Event.new(json) }
```

Don't cache anything read as a signed-in person in a cache other people's pages read from.

## Your own queries

The calls above cover what the apps show. For anything else, run a document of your own and build models from the
result:

```ruby
data = session.graphql(<<~GRAPHQL, { "first" => 5 })
  query Featured($first: Int) {
    events { list(first: $first) { nodes { #{Audience::Kit::Queries.event_fields(Audience::Kit::SchemaShape.everything)} } } }
  }
GRAPHQL
Audience::Kit::Event.list(data.dig("events", "list"))
```

The schema is on the [GraphQL reference](https://developer.audiencekit.com/reference/graphql/). A field a module adds
fails the whole operation in an audience without that module; `shaped_graphql` builds the document from what the
audience has, as the SDK's own calls do.
