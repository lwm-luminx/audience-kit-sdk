## [0.3.0] - 2026-11-26

A rewrite on the AudienceKit GraphQL API, with the same calls as the PHP, Node, Python, Swift and Kotlin SDKs. 0.2
read two REST endpoints the API no longer serves, so every 0.2 call fails; upgrade.

- Add `Audience::Kit::Session`: sign in with Facebook (token or OAuth code), Google, Sign in with Apple or an App
  Review code, or use a service token (`akst_...`, renewed as needed) or an application API key; refresh, sign out
  and delete the account
- Keep the credential in any store: `SessionCredentialStore` for Rails, Rack and Sinatra sessions,
  `MemoryCredentialStore`, or an object of your own
- Read the audience, venues, people, locales, events, event series and the whole community in one call, with
  queries shaped to the audience's modules
- Add the public listings, RSVP, tribes, device registration, cover and coat check, Soapbox news and op-eds,
  calendar subscriptions, chat and moderation
- Add typed, read-only models (`Venue`, `Event`, `Person`, `Article`, `Admission`, `Money`...) that stay readable as
  the API's JSON, and `Coordinate`, `Color` and `CoverPass`
- Every failure is an `Audience::Kit::Error` with a `code` from the API's vocabulary
- `Venue.find` and `Event.find` read over GraphQL with the module-level session, which now needs a host or audience
  ID as well as the token; `AUDIENCEKIT_*` environment variables (the `AUDIENCE_KIT_*` names still work)
- Add guides (signing in, building a website, reference), runnable examples, YARD docs and RBS signatures

## [0.2.0] - 2026-11-25

First release under the AudienceKit SDK License 1.2 (0.1.x were MIT), published from GitHub Actions with
RubyGems trusted publishing.

- Require Ruby 3.2+ and Faraday 2.x
- Move `Event` and `Venue` under `Audience::Kit` and load them from `require "audience-kit"`
- Add `Audience::Kit.configure` (base URL, bearer token) and wrap HTTP errors in `Audience::Kit::Error`
- Add specs and GitHub Actions CI

## [0.1.0] - 2022-01-22

- Initial release
