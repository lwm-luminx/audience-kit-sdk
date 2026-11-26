# Ruby examples

Runnable programs that use the gem the way a site, a job or a bot would. Run them from `ruby/` with the gem's
dependencies installed (`bin/setup`), and the token and host in the environment:

```sh
export AUDIENCEKIT_TOKEN=...              # never commit it
export AUDIENCEKIT_HOST=hotmess.social
bundle exec ruby -Ilib examples/listings_page.rb listings.html
```

| Example | What it does | Token |
| --- | --- | --- |
| [`listings_page.rb`](listings_page.rb) | Writes a static HTML page of the audience's public venues, events and posts. | A service token with `public:read` |
| [`community_export.rb`](community_export.rb) | Writes the whole community (venues, people, locales, events, series) as JSON for a static site generator. | An application API key |
| [`news_digest.rb`](news_digest.rb) | Writes a Markdown digest of a locale's Soapbox news and national news for a newsletter. | An application API key |
| [`member_actions.rb`](member_actions.rb) | Walks through what a signed-in person can do: the next event and who's going, RSVP, a calendar subscription, tonight's cover and a chat message. | A saved sign-in (`AUDIENCEKIT_CREDENTIAL`) |

Each one keeps its work in a module (`ListingsPage.render(session)`, `CommunityExport.to_h(session)`,
`NewsDigest.markdown(session)`, `MemberActions.run(session)`), so you can call it from a Rake task or a Rails job
with a session of your own. The specs in `spec/examples_spec.rb` run each against a stub session.
