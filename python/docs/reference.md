# Python SDK reference

Everything in the `audiencekit` package, by what it is for. `Client` blocks; `AsyncClient` takes the same calls,
awaited. Every call can raise `AudienceKitError`. The models are frozen dataclasses with snake_case fields; each keeps
the JSON it came from in `raw`.

## Client and AsyncClient

### Making one

| Call | What it does |
| --- | --- |
| `Client(configuration, *, credential, http, on_session_change)` | A client for one audience. Every argument is optional. Use it as a context manager, or `close()` it (`aclose()` for `AsyncClient`). |
| `Client.from_environment(environment=None, **options)` | Configured from `AUDIENCEKIT_TOKEN`, `AUDIENCEKIT_BASE_URL`, `AUDIENCEKIT_HOST`, `AUDIENCEKIT_AUDIENCE_ID` and `AUDIENCEKIT_ENVIRONMENT` (`os.environ` unless given a mapping). A token starting `akst_` is a service token; anything else is sent as a bearer token. |

`Configuration` takes `base_url` (`https://api.audiencekit.com`), `host` (the host that names the audience),
`audience_id`, `facebook_app_id` and `environment` (`production` or `staging`). `http` is the `httpx.Client` (or
`httpx.AsyncClient`) to send with; pass your own for timeouts, proxies or a `MockTransport` in tests.
`on_session_change` is called with `("signed_in", credential)`, `("signed_out", None)` or `("session_ended", None)`.

### Signing in and out

| Call | Returns | What it does |
| --- | --- | --- |
| `sign_in_with_facebook(access_token, device)` | `Credential` | Trades a Facebook user access token. |
| `sign_in_with_facebook_code(code, redirect_uri, device)` | `Credential` | Trades the code from Facebook's OAuth dialog. |
| `sign_in_with_google(id_token, device, *, name, access_token)` | `Credential` | Trades a Google ID token. |
| `sign_in_with_apple(identity_token, device, *, first_name, last_name, authorization_code, redirect_uri, nonce)` | `Credential` | Trades a Sign in with Apple credential. |
| `sign_in_with_review_code(code, device)` | `Credential` | Signs an App Reviewer in while the audience is in review. |
| `connect_google(id_token, device)`, `connect_facebook(code, redirect_uri, device)` | `Credential` | Adds a provider to the signed-in account. |
| `use_service_token(token)` | `Credential` | Acts as the audience with a service token, renewed as needed. |
| `use_bearer_token(token)` | | Sends an application API key (or a session JWT) as is. |
| `adopt(credential)` | | Uses a credential minted elsewhere or saved earlier. |
| `refresh_session()` | `Credential` | Re-issues the token for the same session. |
| `sign_out()` | | Forgets the session. |
| `delete_account()` | `bool` | Deletes the signed-in person's account for good, and signs out. |
| `credential`, `is_signed_in` | | The stored session. |
| `session_rejected(token)` | `bool` | Ends the session after a connection the SDK didn't make itself was refused. |

A `DeviceDescription(identifier, type="python", model, version, build)` names the install or server; use
`type="web"` for a browser behind your server. A `Credential` has `token`, `user_id` (`None` for a service session),
`role`, `endpoint`, `audience_id` and `expires_at`; `to_json()` and `Credential.from_json()` save and restore it.

### The audience and its listings

| Call | Returns |
| --- | --- |
| `branding(host=None)` | `Branding`: the audience's public branding (no sign-in) |
| `audience_id()` | `str` |
| `audience()` | `Audience` |
| `me()` | `SelfUser \| None` |
| `venues()`, `people()`, `locales()` | `list[Venue]`, `list[Person]`, `list[Locale]` |
| `closest_locale(Coordinate(latitude, longitude))` | `Locale \| None` |
| `community()` | `Community`: the audience, locales, venues, people, upcoming events and series |
| `events(window="UPCOMING", locale_id, venue_id, first=100)` | `list[Event]`, soonest first, or latest first for `PAST` |
| `event(id)` | `Event \| None` |
| `event_series(locale_id, venue_id, first=100)` | `list[EventSeries]` |
| `node(id)` | `Node \| None`: any record by its ID |

### Public listings

Needs a service token with `public:read`.

| Call | Returns |
| --- | --- |
| `public_listings()` | `list[PublicListing]`, every page |
| `public_listings_page(page)` | `PublicListingsPage`: `listings`, `page_count`, `next_page` |
| `public_listing("venue" \| "event" \| "post", id)` | `PublicListing \| None` |
| `public_tonight(venue_id)` | tonight at the venue, as a screen facing the room shows it (a dict) |

`PublicListing.is_public` says whether anyone may see it in full.

### Members

| Call | Returns | What it does |
| --- | --- | --- |
| `rsvp_event(event_id, state)` | `str` | `ATTENDING`, `MAYBE`, `DECLINED` or `UNSURE`; returns the recorded answer. |
| `cancel_rsvp(event_id)` | `RSVP` | Takes the answer back. |
| `tribes()`, `identify_with_tribe(tag_id, is_private)`, `leave_tribe(tag_id)` | | The tribes people identify with. |
| `register_device(notification_token, app_id, sandbox)` | `bool` | Push notifications for this session's device. |
| `calendar_feed()`, `create_calendar_feed(reset=False)` | `CalendarFeed` | The calendar subscription: `url`, `webcal_url`, `google_url`. |
| `follow_venue_in_calendar(venue_id, following=True)` | `CalendarFeed` | Every event at a venue in their calendar. |
| `delete_calendar_feed()` | `bool` | Ends the subscription. |
| `send_chat_message(text, *, venue_id or locale_id, prompt_id)` | `ChatMessage` | Posts in a venue's or a locale's chat. |
| `remove_chat_message(message_id)` | | Takes back their own message. |
| `report_content(target_type, id, reason=None, block=False)` | `ReportResult` | Reports to the audience's admins; `target_type` is one of `REPORT_TARGETS`, offer `REPORT_REASONS`. |
| `block_user(user_id)`, `unblock_user(user_id)` | | |

### Cover

| Call | Returns | What it does |
| --- | --- | --- |
| `venue_cover(venue_id)` | `VenueCover \| None` | Tonight's `charge` and the viewer's `viewer_admission` and `viewer_coat_check`. |
| `buy_cover(venue_id, amount_cents=None)` | `CoverPurchase` | Starts paying; `amount_cents` on a sliding scale. |
| `buy_coat_check(venue_id, quantity=1)` | `CoverPurchase` | Starts paying for coat check. |
| `confirm_cover(admission_id)` | `Admission` | After Stripe. |
| `pay_cover(admission_id, source_id, verification_token=None)` | `Admission` | With a Square payment token. |
| `refund_admission(admission_id)` | `Admission` | Until it's scanned in or the night ends. |
| `admissions()` | `list[Admission]` | Their passes, newest first. |

### News (Soapbox)

Every call returns nothing, rather than failing, for an audience without Soapbox.

| Call | Returns |
| --- | --- |
| `articles(locale_id, publication_id, first)` | `list[Article]`, pinned first, then newest |
| `articles_page(locale_id, publication_id, first=20, after)` | `ArticlesPage`: `articles`, `end_cursor`, `has_next_page` |
| `national_articles(locale_id, first)` | `list[Article]` |
| `article(id)` | `Article \| None`, with `body` and what it's about |
| `articles_about("venue" \| "event" \| "person" \| "locale", id, first)` | `list[Article]` |
| `publications()`, `local_publications(locale_id)` | `list[Publication]` |
| `publication(id)` | `Publication \| None` |
| `my_op_eds()` | `list[Article]` with `status` and `review_note` |
| `submit_op_ed(publication_id, title, body, *, summary, byline)` | `Article` |

### Your own operations

| Call | What it does |
| --- | --- |
| `graphql(query, variables, operation_name, endpoint)` | Runs any document and returns its `data`. |
| `run(Operation(...), endpoint)` | Runs one of your own operations with the retry after an `undefinedField`. |
| `schema_fields(types, endpoint)` | The fields each type has in the audience's schema, cached until sign-out. |
| `request(method, path, *, params, body, authenticated)` | Calls a REST endpoint with the session and returns the body. |

`audiencekit.operations` builds every operation the client runs, so a service can run them with its own options.

## Helpers

| Function | What it does |
| --- | --- |
| `cover_pass_code(admission_id, pass_secret, epoch_seconds=None)` | The door code the apps show (`HMC1.…`). |
| `is_cover_pass_code(code)` | Whether a scanned string is one. |
| `cover_pass.window(epoch_seconds)`, `cover_pass.seconds_until_next_window(epoch_seconds)` | The code's 30-second window. |
| `Coordinate.from_wkt(wkt)` | A point from the API's WKT. |
| `REPORT_REASONS`, `INTIMATE_IMAGE_REASON`, `REPORT_TARGETS` | What to offer when reporting. |

`__version__`, `API_VERSION` and `PRODUCTION_BASE_URL` say which SDK and API contract this is.

## Errors

`AudienceKitError` has a `code`: from the API, `UNAUTHENTICATED`, `FORBIDDEN`, `NOT_FOUND`, `INVALID` (with per-field
messages in `fields`), `RATE_LIMITED`, `CONFLICT` and `INTERNAL`; from the SDK, `NOT_SIGNED_IN`, `SIGN_IN_REJECTED`,
`NETWORK`, `DECODING`, `MISSING_CONFIGURATION` and `UPDATE_REQUIRED`. It also has the `message`, the HTTP `status` when
there was one, and the GraphQL `errors` (each a `GraphQLError`). `is_unauthenticated` and `is_undefined_field` answer
the common questions.
