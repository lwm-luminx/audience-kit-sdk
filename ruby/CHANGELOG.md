## [Unreleased]

- Require Ruby 3.2+ and Faraday 2.x
- Move `Event` and `Venue` under `Audience::Kit` and load them from `require "audience-kit"`
- Add `Audience::Kit.configure` (base URL, bearer token) and wrap HTTP errors in `Audience::Kit::Error`
- Add specs and GitHub Actions CI

## [0.1.0] - 2022-01-22

- Initial release
