# Python examples

Small programs built on the `audiencekit` package, one per thing a site or service does. Each defines the functions
it is built around, so the SDK's tests run them against a fake API, and runs as a program when started directly. They
use only the standard library besides `audiencekit`:

```sh
pip install audiencekit
AUDIENCEKIT_TOKEN=akst_… AUDIENCEKIT_HOST=hotmess.social python listings_site.py
```

| File | What it shows |
| --- | --- |
| [`listings_site.py`](listings_site.py) | A page of the audience's public listings, read with a service token and cached for five minutes |
| [`news_digest.py`](news_digest.py) | A Markdown digest of a locale's news and its national news, for a newsletter job |
| [`facebook_sign_in.py`](facebook_sign_in.py) | Signing people in with Facebook on a server, one session per browser |
| [`member_actions.py`](member_actions.py) | What a signed-in member does: RSVP, calendar links, the door pass and reporting |
| [`community_export.py`](community_export.py) | The whole community as JSON, for a static site generator |
