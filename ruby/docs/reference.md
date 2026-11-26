# Ruby SDK reference

Everything in the `audience-kit` gem, by what it is for. Everything is in the `Audience::Kit` namespace, and every call
can raise `Audience::Kit::Error`. The YARD reference on [RubyDoc.info](https://rubydoc.info/gems/audience-kit) has
each method's parameters and return types; `bundle exec rake yard` builds it locally.

## Session

### Making one

| Call | What it does |
| --- | --- |
| `Session.new(configuration:, store:, http:)` | A session for one audience. `store:` defaults to a `MemoryCredentialStore`; `http:` is a Faraday connection of your own (one is made when it's nil). |
| `Session.from_env(env = ENV, http:)` | Configured from `AUDIENCEKIT_TOKEN`, `AUDIENCEKIT_BASE_URL`, `AUDIENCEKIT_AUDIENCE_ID`, `AUDIENCEKIT_HOST` and `AUDIENCEKIT_ENVIRONMENT`. A token starting `akst_` is a service token; anything else is sent as a bearer token. |
| `Session.build(configuration:, token:, http:)` | The same, from values you already have. |

`Configuration.new` takes `base_url:` (`https://api.audiencekit.com`), `host:` (the host that names the audience),
`audience_id:`, `facebook_app_id:`, `environment:` (`Environment::PRODUCTION` or `Environment::STAGING`) and
`trusted_credential_origins:`. It's a `Data`, so `configuration.with(host: "...")` makes a changed copy.

### Signing in and out

| Call | Returns | What it does |
| --- | --- | --- |
| `sign_in_with_facebook_token(access_token, device:)` | `Credential` | Trades a Facebook user access token. |
| `sign_in_with_facebook_code(code, redirect_uri:, device:, facebook_app_id: nil)` | `Credential` | Trades the code from Facebook's OAuth dialog. |
| `sign_in_with_google(id_token, device:, name: nil, access_token: nil)` | `Credential` | Trades a Google ID token. |
| `sign_in_with_apple(identity_token, device:, authorization_code:, redirect_uri:, nonce:, first_name:, last_name:)` | `Credential` | Trades a Sign in with Apple credential; every keyword but `device:` is optional. |
| `sign_in_with_review_code(code, device:)` | `Credential` | Signs an App Reviewer in while the audience is in review. |
| `connect_facebook(code, redirect_uri:, device:)`, `connect_google(id_token, device:)` | `Credential` | Adds a provider to the signed-in account. |
| `use_service_token(token)` | `Credential` | Acts as the audience with a service token, renewed as needed. |
| `use_bearer_token(token)` | | Sends an application API key (or a session JWT) as is. |
| `adopt(credential)` | | Uses a credential minted elsewhere, or one you stored. |
| `refresh_session` | `Credential` | Re-issues the token for the same session. |
| `switch_audience(audience_id)` | `Credential` | Moves a platform-console session to another audience. |
| `sign_out` | | Forgets the credential and revokes the token. |
| `delete_account` | `Boolean` | Deletes the signed-in person's account for good. |
| `signed_in?`, `credential`, `session_token` | | The stored session. |
| `session_rejected(token)` | `Boolean` | Forgets the session after a connection the SDK didn't make itself was refused. |

`DeviceDescription.new(identifier:, type: "web", model: nil, version: nil, build: nil)` describes the browser or
server signing in.

### The audience and its listings

| Call | Returns |
| --- | --- |
| `branding(host:, app:)` | `Hash`: the audience's public branding (no sign-in) |
| `audience_id` | `String` |
| `audience` | `Audience` |
| `me` | `SelfUser` or nil |
| `venues` | `Array<Venue>` |
| `venue_detail(id, recent_messages: 20)` | `Venue` or nil, with its profile, chat and upcoming events |
| `people` | `Array<Person>` |
| `locales` | `Array<Locale>` |
| `closest_locale(coordinate)` | `Locale` or nil |
| `report_location(coordinate, fields)` | `Hash` of the fields you select |
| `events(window: "UPCOMING", locale_id: nil, venue_id: nil, first: 100)` | `Array<Event>`; `window: "PAST"` for what has ended |
| `event(id)` | `Event` or nil |
| `event_series(locale_id: nil, venue_id: nil, first: 100)` | `Array<EventSeries>` |
| `community` | `Community`: the audience, locales, venues, people, events and series |
| `node_type(id)` | `String` or nil: which type a global ID names |

### Public listings (service token with `public:read`)

| Call | Returns |
| --- | --- |
| `public_listings` | `Array<PublicListing>`: every page |
| `public_listings_page(page = 1)` | `PublicListingsPage` (`listings`, `page_count`, `next_page`) |
| `public_listing(:venue \| :event \| :post, id)` | `PublicListing` or nil |
| `public_tonight(venue_id)` | `Hash`: tonight at a venue, as a room screen shows it |

### RSVP, tribes and notifications

| Call | Returns |
| --- | --- |
| `rsvp_event(event_id, "ATTENDING" \| "MAYBE" \| "DECLINED" \| "UNSURE")` | `String`: the answer as stored |
| `cancel_rsvp(event_id)` | `EventRSVP` |
| `event_rsvp(event_id, first: 50)` | `EventRSVP` or nil, with the first attendees |
| `tribes` | `Tribes` (`tribes`, an `Array<Tag>`; `mine`, an `Array<TribeIdentification>`) |
| `identify_with_tribe(tag_id, private: nil)`, `leave_tribe(tag_id)` | `Array<TribeIdentification>` |
| `register_device(notification_token, app_id: nil, sandbox: nil)` | `Boolean` |

### Cover and coat check

| Call | Returns |
| --- | --- |
| `venue_cover(venue_id)` | `VenueCover` or nil: tonight's charge, and the viewer's pass and coat check ticket |
| `venue_offers(venue_id, night: nil)` | `Array<AdmissionOffer>`: every way in on a night |
| `buy_cover(venue_id, amount_cents: nil, currency: "usd")` | `CoverPurchase` |
| `buy_coat_check(venue_id, quantity: 1)` | `CoverPurchase` |
| `pay_cover(admission_id, source_id:, verification_token: nil)` | `Admission` (Square) |
| `confirm_cover(admission_id)` | `Admission` (Stripe) |
| `refund_admission(admission_id)` | `Admission` |
| `admissions` | `Array<Admission>` |

### News (Soapbox)

| Call | Returns |
| --- | --- |
| `articles(locale_id: nil, publication_id: nil, first: nil)` | `Array<Article>` |
| `articles_page(locale_id: nil, publication_id: nil, first: 20, after: nil)` | `ArticlesPage` (`articles`, `end_cursor`, `next_page?`) |
| `national_articles(locale_id: nil, first: nil)` | `Array<Article>` |
| `article(id)` | `Article` or nil, with its body and subjects |
| `articles_about(:venue \| :event \| :person \| :locale, id, first: nil)` | `Array<Article>` |
| `publications`, `local_publications(locale_id)` | `Array<Publication>` |
| `publication(id)` | `Publication` or nil |
| `my_op_eds` | `Array<Article>`, with `status` and `review_note` |
| `submit_op_ed(publication_id, title:, body:, summary: nil, byline: nil)` | `Article` |

Every Soapbox call returns an empty Array or nil for an audience without Soapbox.

### Calendar subscriptions

| Call | Returns |
| --- | --- |
| `calendar_feed` | `CalendarFeed` or nil |
| `create_calendar_feed(reset: false)` | `CalendarFeed` |
| `follow_venue_in_calendar(venue_id, following: true)` | `CalendarFeed` |
| `delete_calendar_feed` | `Boolean` |

### Chat and moderation

| Call | Returns |
| --- | --- |
| `send_chat_message(message, venue_id:)` or `(message, locale_id:)`, with `prompt_id:` | `ChatMessage` |
| `remove_chat_message(message_id)` | `String`: the removed ID |
| `report_content(ReportTarget::..., id, reason: nil, block: false)` | `ReportResult` (`reported?`, `blocked?`) |
| `block_user(user_id)`, `unblock_user(user_id)` | |

`ReportTarget` has the targets (`MESSAGE`, `PERSON`, `PHOTO`, `PING`, `PRIVATE_MESSAGE`, `POST`, `POST_COMMENT`,
`VENUE`) and `REASONS`, the reasons the apps offer. Keep `ReportTarget::INTIMATE_IMAGE`'s wording: the API gives those
reports a 48-hour deadline.

### Your own operations

| Call | Returns |
| --- | --- |
| `graphql(document, variables = nil, operation_name: nil, endpoint: GraphQLEndpoint::CONSUMER)` | `Hash`: the response's `data` |
| `shaped_graphql(types, variables, operation_name) { \|shape\| document }` | `Hash`: built for the audience's modules |
| `schema_fields(types)`, `cached_schema_fields(types)` | `Hash{String => Array<String>}` |
| `request(path, method: :get, query: {}, body: nil, authenticated: true, headers: {})` | `String`: a REST response's body |
| `url(string)` | `String` or nil: a URL the API sent, made absolute |

`Queries` has every document the SDK sends, and the field lists to build your own from
(`Queries.event_fields(shape)`, `Queries::ADMISSION_FIELDS`, `Queries.chat_room(kind)` for an Action Cable client...).
`SchemaShape.everything` asks for every module's fields; `Queries.all` returns every document, by name.

## The module-level session

| Call | What it does |
| --- | --- |
| `Audience::Kit.configure { \|c\| ... }` | Sets `token`, `host`, `audience_id` and `base_url` for the shared session (the environment comes from `AUDIENCEKIT_ENVIRONMENT`). |
| `Audience::Kit.session` | The shared session, made from `configure` or the environment on first use. |
| `Audience::Kit.session = session` | Uses a session you made. |
| `Audience::Kit.query(document, variables = nil)` | `graphql` on the shared session. |
| `Audience::Kit.reset!` | Forgets the shared session and configuration (for tests). |
| `Venue.find(id)`, `Event.find(id)` | A venue's or an event's page with the shared session; raises `NOT_FOUND` when there's none. |

## Models

Each model has snake_case, read-only readers, and is also readable as the API's JSON (`model["field"]`,
`model.dig(...)`, `to_h`, `to_json`; `data` is kept for 0.2 code). `Model.from(json)` and `Model.list(json)` build them
from Hashes you cached. Times are `Time`, money is `Money`, and yes-or-no readers end in `?`.

| Model | Readers |
| --- | --- |
| `Audience` | `id`, `name`, `subdomain`, `theme`; `color(token, dark: false)` |
| `SelfUser` | `id`, `name`, `first_name`, `last_name`, `email_address`, `admin?`, `presence` |
| `Profile` | `id`, `name`, `avatar_url` |
| `Locale` | `id`, `name`, `label`, `city_names`, `banner_url`, `place_id` |
| `Location` | `id`, `address`, `place_id`; `coordinate` |
| `Venue` | `id`, `name`, `hidden?`, `order`, `photo_url`, `banner_url`, `locale`, `location`, `tags`, `facebook_page`; on its page `description`, `address`, `phone`, `website`, `social_links`, `chat_open`, `recent_messages`, `upcoming_events`; `coordinate` |
| `Person` | `id`, `name`, `avatar_url`, `banner_url`, `order`, `global?`, `like_required?`, `tags`, `locales`, `facebook_page`, `home_venue`, `involvements` |
| `Event` | `id`, `name`, `description`, `start_at`, `end_at`, `featured?`, `canceled?`, `banner_url`, `source_url`, `locale`, `tags`, `venue_name`, `venue`, `rsvp`, `rsvp_count`, `hosts`, `lineup`, `jockeys`, `jockey_label`, `ticket_url`, `offers`, `cover`; `effective_hosts`, `ended?` |
| `EventSeries` | `id`, `name`, `description`, `recurrence_text`, `starts_on`, `start_time`, `time_zone`, `duration_minutes`, `banner_url`, `locale`, `tags`, `venue_name`, `venue` |
| `EventRSVP` | `count`, `mine`, `mine_source`, `going`, `interested`, `tickets`, `attendees`; `going?`, `attendee_profiles` |
| `Tag` | `id`, `name`, `color_hex`, `tribe?`; `color` |
| `TribeIdentification` | `private?`, `tag` |
| `Money` | `cents`, `currency`; `amount`, `format` (`"$12.00"`, also `to_s`) |
| `CoverCharge` | `amount`, `fee`, `total`, `night`, `from`, `payable?`, `event`, `coat_check`, `scale_min`, `scale_max`, `scale_suggested`; `sliding_scale?`, `coat_check?` |
| `Admission` | `id`, `status`, `kind`, `night`, `quantity`, `tier`, `claim_check_number`, `amount`, `fee`, `total`, `refundable?`, `pass_secret`, `scan_count`, `checked_in_at`, `created_at`, `profile`, `venue`, `event`; `paid?`, `pass_code` |
| `AdmissionOffer` | `price`, `url`, `seller_key`, `seller_name` |
| `CoverPurchase` | `admission`, `provider`, `payment_intent_client_secret`, `publishable_key`, `stripe_account_id`, `square_application_id`, `square_location_id` |
| `VenueCover` | `id`, `name`, `charge`, `viewer_admission`, `viewer_coat_check` |
| `ChatMessage` | `id`, `body`, `name`, `user_id`, `avatar_url`, `photo_url`, `sent_at`, `role`, `kind`, `title`, `pinned?` |
| `Article` | `id`, `slug`, `title`, `summary`, `byline`, `kind`, `published_at`, `edited?`, `pinned?`, `teaser?`, `canonical_url`, `disclosure`, `hero_photo_url`, `hero_alt_text`, `publication`, `body`, `subjects`, `viewer_ad_free?`, `featured_nationally?`, `status`, `review_note`, `submitted_at` |
| `Publication` | `id`, `name`, `masthead`, `about`, `website_url`, `photo_url`, `trusted?`, `accepts_op_eds?`, `op_ed_guidelines`, `locale`, `person`, `ad_free_offered?`, `ad_free_tip_cents`, `ad_free_days` |
| `CalendarFeed` | `url`, `webcal_url`, `google_url`, `venue_ids`; `follows?(venue_id)` |
| `PublicListing` | `kind`, `id`, `path`, `visibility`, `title`, `description`, `address`, `phone`, `website`, `listed`, `image`, `start_at`, `end_at`, `venue_name`, `ticket_url`, `canceled`, `cover_cents`; `public?` |
| `Page` | A Facebook Page: `id`, `name`, `photo_url`, `banner_url` |

`ArticlesPage`, `PublicListingsPage`, `Community`, `ReportResult` and `Tribes` are `Data` value objects.

## Credentials and stores

`Credential` has `token`, `user_id` (nil for a service session), `audience_id`, `role` (`member`, `admin`,
`venue_device`, `service`...), `endpoint`, `venue_device_id`, `expires_at`, `api_version`, `scopes` and `audience`, with
`expired?`, `expires_within?(seconds)`, `service?`, `scope?(scope)`, `origin`, `Credential.from_h` and `to_h`. Its
`inspect` leaves the token out.

A credential store is any object with `load`, `save(credential)` and `delete` (`CredentialStore` documents the
interface). `MemoryCredentialStore` lasts as long as the object and `SessionCredentialStore.new(session, key:)` keeps
the credential in a Rails, Rack or Sinatra session.

## Helpers

| Name | What it does |
| --- | --- |
| `Coordinate` | A latitude and longitude, with an optional beacon. `Coordinate.from_wkt`, `to_wkt`, `to_input`, `distance_to` in meters. |
| `Color` | `Color.from_hex`, `Color.from_theme(theme, token, dark:)`, `to_css`, `to_hex`. |
| `CoverPass` | `CoverPass.code(admission_id, pass_secret, epoch_seconds = nil)` makes a pass's door code (`HMC1.<id>.<window>.<signature>`), the same one the apps show; `code?`, `window`, `seconds_until_next_window`. |
| `Audience::Kit` | `VERSION`, `API_VERSION`, `PRODUCTION_BASE_URL`, the header names, `client_header` and `older?`. |

## Errors

`Error` carries `code` (a constant on the class), the HTTP `status`, the GraphQL `errors` (`GraphQLError`s with
`message`, `path`, `extensions` and `code`), for `INVALID` per-field messages in `fields`, and for `UPDATE_REQUIRED` the
`minimum_sdk_version`. `unauthenticated?` and `undefined_field?` answer the common questions.
