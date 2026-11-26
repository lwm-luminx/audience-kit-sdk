# Node examples

Small programs built on the `audience-kit` package, one per thing a site or service does. Each exports the function it
is built around, so the SDK's tests run it against a stub API, and runs as a program when started directly:

```sh
npm install audience-kit
AUDIENCEKIT_TOKEN=akst_… AUDIENCEKIT_HOST=hotmess.social node --experimental-strip-types listings-site.ts
```

| File | What it shows |
| --- | --- |
| [`listings-site.ts`](listings-site.ts) | A page of the audience's public listings, read with a service token and cached for five minutes |
| [`news-digest.ts`](news-digest.ts) | A Markdown digest of a locale's news and its national news, for a newsletter job |
| [`facebook-sign-in.ts`](facebook-sign-in.ts) | Signing people in with Facebook on a server, one session per browser |
| [`member-actions.ts`](member-actions.ts) | What a signed-in member does: RSVP, calendar links, the door pass and reporting |
| [`community-export.ts`](community-export.ts) | The whole community as JSON, for a static site generator |
