# Building a website with PHP

A venue's site, a city guide, a WordPress plugin or a newsletter job can be built from what an audience lists, with
the same calls the apps make. This page covers reading as the audience (no one signed in), the public listings,
Soapbox news and the things a signed-in visitor can do on a site.

## Read as the audience: service tokens

An admin mints a service token in the audience's console (`akst_<prefix>_<secret>`) with the scopes the site needs,
`public:read` for the public listings. Keep it in the environment, never in the repository:

```sh
AUDIENCEKIT_TOKEN=akst_…
AUDIENCEKIT_HOST=hotmess.social
```

```php
use AudienceKit\AudienceSession;

$audienceKit = AudienceSession::fromEnvironment();
```

`fromEnvironment()` also reads `AUDIENCEKIT_BASE_URL`, `AUDIENCEKIT_AUDIENCE_ID` and `AUDIENCEKIT_ENVIRONMENT`
(`staging` for a staging build). With a token in code instead:

```php
$audienceKit = new AudienceSession(new Configuration(host: 'hotmess.social'));
$audienceKit->useServiceToken(getenv('MY_TOKEN'));
```

The SDK trades the token at `POST /v1/token/service` for an hour-long session, trades it again a minute before that
runs out, and once more if the API refuses the session (after a key rotation, say). A token an admin revoked throws
`AudienceKitException` with `UNAUTHENTICATED`. An application API key works the same way through `AUDIENCEKIT_TOKEN`
or `useBearerToken()`: it is sent as is.

## The public listings

What the audience shows anyone, as its own websites show it: up to 500 venues, then events, then posts, a page at a
time. Plain text, ready for a template:

```php
foreach ($audienceKit->publicListings() as $listing) {
    if (!$listing->isPublic()) {
        continue;                           // "community" listings show in full only to members
    }
    echo match ($listing->kind) {
        'venue' => "<h2>{$listing->title}</h2><p>{$listing->address}</p>",
        'event' => "<h3>{$listing->title}</h3><time>{$listing->startAt?->format('D M j, g:ia')}</time>",
        'post' => "<article><h3>{$listing->title}</h3><p>{$listing->description}</p></article>",
        default => '',
    };
}
```

`publicListingsPage($page)` reads one page (with `nextPage` for the next), `publicListing('venue', $id)` one listing
(null when it's gone), and `publicTonight($venueId)` what a screen facing the room shows: tonight's event, who's on and
what's next.

## The community in one call

For a site that renders from the richer GraphQL models (venues with their locales, points and tags; events with their
venues, hosts and tickets), `community()` reads the audience, its locales, venues, people, upcoming events and event
series together. A part whose module the audience doesn't have comes back empty.

```php
$community = $audienceKit->community();

foreach ($community->venues as $venue) {
    $point = $venue->coordinate();                     // AudienceKit\Coordinate, for a map
    $tags = array_map(fn ($tag) => $tag->name, $venue->tags);
}

$accent = $community->audience?->color('accent');      // AudienceKit\Color from the audience's theme
echo $accent?->toCss();                                // rgba(255, 51, 102, 1)
```

The individual calls are there too: `venues()`, `people()`, `locales()`, `events($window, $localeId, $venueId)`,
`eventSeries()`, `event($id)` and `venueDetail($id)`.

Events have their own time zone and may have no end. `$event->startAt` is a `DateTimeImmutable` in UTC; show it in the
locale's zone with `->setTimezone(new DateTimeZone('America/Denver'))`. `$event->hasEnded()` says whether it is over,
and `$event->effectiveHosts()` who runs the night: its hosts or, when nobody else is linked to it, its KJ, DJ or VJ.

## News

Audiences with Soapbox carry local news and op-eds from publications they trust:

```php
// The latest, pinned first, for a locale (or one publication).
foreach ($audienceKit->articles(localeId: $locale->id, first: 10) as $article) {
    printf('<a href="/news/%s">%s</a> <small>%s</small>', $article->slug, $article->title, $article->publication?->name);
}

// "Show more": page through with the cursor.
$page = $audienceKit->articlesPage(localeId: $locale->id, after: $_GET['after'] ?? null);
if ($page->hasNextPage) {
    echo '<a href="?after=' . urlencode($page->endCursor) . '">Show more</a>';
}

// One article, with its Markdown body and what it is about.
$article = $audienceKit->article($id);
```

Also `nationalArticles()`, `articlesAbout('venue' | 'event' | 'person' | 'locale', $id)` for "In the news" on a
listing's page, `publications()`, `localPublications($localeId)` and `publication($id)`. Show `$article->disclosure`
when there is one, and link `$article->canonicalUrl` when `$article->teaser` is true: the rest of the article is on
the publication's site. A signed-in reader can send a publication that accepts them an op-ed with `submitOpEd()`, and
follow it with `myOpEds()`.

Every Soapbox call returns nothing, rather than failing, for an audience without Soapbox.

## Things a signed-in visitor can do

Once someone has [signed in](sign-in.md), a site can do what the apps do:

- RSVP: `rsvpEvent($eventId, 'ATTENDING')`, `cancelRsvp($eventId)` and `eventRsvp($eventId)` for who's going.
- Calendar: `createCalendarFeed()` returns links (`$feed->url`, `webcalUrl`, `googleUrl`) that add every event they're
  going to to their own calendar, and `followVenueInCalendar($venueId)` adds every event at a venue.
- Cover: `venueCover($venueId)` says tonight's charge; `buyCover($venueId)` (with an amount on a sliding scale) or
  `buyCoatCheck($venueId, $coats)` starts paying with the venue's provider. For Stripe, confirm
  `paymentIntentClientSecret` with Stripe.js and call `confirmCover()`; for Square, tokenize with the Web Payments SDK
  and call `payCover()`. `$admission->passCode()` is the code to show at the door as a QR code; it changes every 30
  seconds, so render it in the page and refresh it, rather than caching it.
- Chat: `sendChatMessage()`, `removeChatMessage()`, and `reportContent()`, `blockUser()` and `unblockUser()` so people
  can report what they see. Offer `ReportTarget::REASONS` as the reasons.

## Caching

Listings change a few times a day, so cache what the page renders, not the session. A PSR-16 cache, APCu or a
WordPress transient all work:

```php
$events = apcu_entry('audiencekit.events', fn () => array_map(
    fn ($event) => $event->raw(),                      // cache the JSON; rebuild models when reading
    $audienceKit->events(),
), 300);
$events = array_map(fn (array $json) => new AudienceKit\Model\Event($json), $events);
```

Don't cache anything read as a signed-in person in a cache other people's pages read from.

## WordPress

The SDK needs PHP 8.1 and a PSR-18 HTTP client. In a plugin, require it with Composer and give it a client
(`composer require audiencekit/audiencekit guzzlehttp/guzzle`), keep the service token in `wp-config.php`
(`putenv('AUDIENCEKIT_TOKEN=akst_…')` or a constant you pass to `useServiceToken()`), and cache in transients:

```php
add_shortcode('audiencekit_events', function (): string {
    $events = get_transient('audiencekit_events');
    if ($events === false) {
        $events = array_map(fn ($e) => $e->raw(), AudienceKit\AudienceSession::fromEnvironment()->events());
        set_transient('audiencekit_events', $events, 5 * MINUTE_IN_SECONDS);
    }
    $html = '<ul class="audiencekit-events">';
    foreach ($events as $json) {
        $event = new AudienceKit\Model\Event($json);
        $html .= sprintf('<li>%s, %s</li>', esc_html($event->name), esc_html($event->venueName ?? ''));
    }

    return $html . '</ul>';
});
```
