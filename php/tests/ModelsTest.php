<?php

declare(strict_types=1);

namespace AudienceKit\Tests;

use AudienceKit\Model\Admission;
use AudienceKit\Model\Article;
use AudienceKit\Model\ArticlesPage;
use AudienceKit\Model\Audience;
use AudienceKit\Model\CalendarFeed;
use AudienceKit\Model\CoverCharge;
use AudienceKit\Model\Event;
use AudienceKit\Model\EventRSVP;
use AudienceKit\Model\EventSeries;
use AudienceKit\Model\Money;
use AudienceKit\Model\Person;
use AudienceKit\Model\PublicListing;
use AudienceKit\Model\PublicListingsPage;
use AudienceKit\Model\Publication;
use AudienceKit\Model\Tag;
use AudienceKit\Model\Venue;
use AudienceKit\Model\VenueCover;
use LogicException;
use PHPUnit\Framework\TestCase as BaseTestCase;

final class ModelsTest extends BaseTestCase
{
    public function testAModelIsAlsoItsArray(): void
    {
        $venue = new Venue(['id' => 'v1', 'name' => 'Club', 'extra' => ['nested' => 1]]);
        self::assertSame('v1', $venue['id']);
        self::assertSame(1, $venue['extra']['nested']);
        self::assertTrue(isset($venue['name']));
        self::assertFalse(isset($venue['missing']));
        self::assertNull($venue['missing']);
        self::assertSame('{"id":"v1","name":"Club","extra":{"nested":1}}', json_encode($venue));
        self::assertNull(Venue::from(null));
        self::assertSame([], Venue::list('nope'));
        self::assertSame([], Venue::list(['nodes' => null]));
        self::assertCount(1, Venue::list(['nodes' => [['id' => 'a'], null]]));
    }

    public function testModelsAreReadOnly(): void
    {
        $venue = new Venue(['id' => 'v1']);
        try {
            $venue['id'] = 'v2';
            self::fail('Expected an exception.');
        } catch (LogicException) {
        }
        $this->expectException(LogicException::class);
        unset($venue['id']);
    }

    public function testVenue(): void
    {
        $venue = new Venue([
            'id' => 'v1', 'name' => 'Club', 'hidden' => false, 'order' => '3', 'photoUrl' => 'p',
            'locale' => ['id' => 'l1', 'name' => 'Salt Lake', 'cityNames' => ['SLC', 4], 'profile' => ['places' => ['placeId' => 'gp']]],
            'location' => ['id' => 'loc', 'point' => 'POINT (-111.89 40.76)', 'address' => '1 Main', 'places' => ['placeId' => 'g2']],
            'tags' => [['id' => 't', 'name' => 'Bears', 'color' => '#123456', 'tribe' => true]],
            'profile' => [
                'facebook' => ['page' => ['id' => 'fb', 'name' => 'Club FB']],
                'address' => '1 Main', 'phone' => '555', 'website' => 'https://club',
                'socialLinks' => ['nodes' => [['id' => 's', 'provider' => 'INSTAGRAM'], null]],
            ],
            'description' => 'Dance',
            'chat' => ['open' => true, 'recentMessages' => ['nodes' => [['id' => 'm', 'message' => 'hi', 'sentAt' => '2026-11-24T20:00:00Z', 'pinned' => true]]]],
            'events' => ['upcoming' => ['nodes' => [['id' => 'e']]]],
        ]);
        self::assertSame(3, $venue->order);
        self::assertSame('gp', $venue->locale?->placeId);
        self::assertSame(['SLC'], $venue->locale?->cityNames);
        self::assertSame(40.76, $venue->coordinate()?->latitude);
        self::assertSame('g2', $venue->location?->placeId);
        self::assertTrue($venue->tags[0]->tribe);
        self::assertSame('#123456', $venue->tags[0]->color()?->toHex());
        self::assertSame('Club FB', $venue->facebookPage?->name);
        self::assertSame('555', $venue->phone);
        self::assertCount(1, $venue->socialLinks);
        self::assertTrue($venue->chatOpen);
        self::assertSame('hi', $venue->recentMessages[0]->body);
        self::assertTrue($venue->recentMessages[0]->pinned);
        self::assertSame('2026-11-24', $venue->recentMessages[0]->sentAt?->format('Y-m-d'));
        self::assertSame('e', $venue->upcomingEvents[0]->id);
        $bare = new Venue(['id' => 'v2', 'location' => ['point' => null]]);
        self::assertNull($bare->chatOpen);
        self::assertNull($bare->coordinate());
        self::assertNull((new Tag(['id' => 't']))->color());
    }

    public function testPersonAndAudience(): void
    {
        $person = new Person([
            'id' => 'p', 'name' => 'DJ', 'global' => true, 'locales' => [['id' => 'l']],
            'venues' => ['home' => ['id' => 'v', 'name' => 'Home']],
            'events' => ['involvements' => ['edges' => [['role' => 'DJ', 'node' => ['id' => 'e']]]]],
        ]);
        self::assertTrue($person->global);
        self::assertSame('Home', $person->homeVenue?->name);
        self::assertSame('DJ', $person->involvements[0]['role']);
        self::assertSame('l', $person->locales[0]->id);
        $audience = new Audience(['id' => 'a', 'name' => 'Hot Mess', 'theme' => ['light' => [['name' => 'accent', 'value' => '#ff0000']]]]);
        self::assertSame('#ff0000', $audience->color('accent')?->toHex());
    }

    public function testEvent(): void
    {
        $event = new Event([
            'id' => 'e', 'name' => 'Karaoke', 'startAt' => '2026-11-25T03:00:00Z', 'endAt' => 'not a date',
            'venue' => ['name' => 'SunTrapp', 'venue' => ['id' => 'v']],
            'rsvp' => ['mine' => 'ATTENDING', 'count' => 12],
            'people' => ['hosts' => ['nodes' => []], 'lineup' => ['nodes' => []], 'jockeys' => ['nodes' => [['id' => 'kj', 'name' => 'Dalton']]], 'jockeyLabel' => 'KJ'],
            'tickets' => ['url' => 'https://t', 'offers' => ['nodes' => [['price' => ['cents' => 500, 'currency' => 'USD'], 'seller' => ['key' => 'cover', 'name' => 'Cover']]]],
                'cover' => ['charge' => ['amount' => ['cents' => 1000, 'currency' => 'usd'], 'payable' => true]]],
        ]);
        self::assertSame('SunTrapp', $event->venueName);
        self::assertSame('v', $event->venue?->id);
        self::assertSame(12, $event->rsvpCount);
        self::assertSame('ATTENDING', $event->rsvp);
        self::assertNull($event->endAt);
        self::assertSame('Dalton', $event->effectiveHosts()[0]->name, 'a lone jockey is the host');
        self::assertSame('KJ', $event->jockeyLabel);
        self::assertSame('cover', $event->offers[0]->sellerKey);
        self::assertSame('usd', $event->offers[0]->price?->currency);
        self::assertTrue($event->cover?->payable);
        self::assertTrue($event->hasEnded(new \DateTimeImmutable('2026-11-26')));
        self::assertFalse($event->hasEnded(new \DateTimeImmutable('2026-11-24')));
        self::assertFalse((new Event(['id' => 'x']))->hasEnded());
        $hosted = new Event(['id' => 'y', 'people' => ['hosts' => ['nodes' => [['id' => 'h']]], 'jockeys' => ['nodes' => [['id' => 'j']]]]]);
        self::assertSame('h', $hosted->effectiveHosts()[0]->id);
        $series = new EventSeries(['id' => 's', 'recurrenceText' => 'Every Tuesday', 'durationMinutes' => 180, 'venue' => ['name' => 'Bar']]);
        self::assertSame('Every Tuesday', $series->recurrenceText);
        self::assertSame(180, $series->durationMinutes);
        self::assertSame('Bar', $series->venueName);
    }

    public function testMoney(): void
    {
        $money = new Money(['cents' => 1250, 'currency' => 'USD']);
        self::assertSame(12.5, $money->amount());
        self::assertSame('usd', $money->currency);
        self::assertStringContainsString('12.50', $money->format());
        self::assertStringContainsString('12.50', (new Money(['cents' => 1250, 'currency' => 'xyz']))->format());
    }

    public function testCover(): void
    {
        $charge = new CoverCharge([
            'amount' => ['cents' => 1000, 'currency' => 'usd'], 'from' => '2026-11-24T21:00:00-07:00', 'night' => '2026-11-24',
            'coatCheck' => ['payable' => true], 'scale' => ['min' => ['cents' => 500], 'max' => ['cents' => 2000], 'suggested' => ['cents' => 1000]],
        ]);
        self::assertTrue($charge->isSlidingScale());
        self::assertTrue($charge->hasCoatCheck());
        self::assertSame(2000, $charge->scaleMax?->cents);
        self::assertFalse((new CoverCharge([]))->isSlidingScale());
        self::assertFalse((new CoverCharge([]))->hasCoatCheck());

        $admission = new Admission(['id' => 'adm', 'status' => 'PAID', 'kind' => 'COAT_CHECK', 'quantity' => 2,
            'claimCheckNumber' => '42', 'passSecret' => base64_encode('secret'), 'profile' => ['id' => 'u', 'name' => 'Ada']]);
        self::assertTrue($admission->isPaid());
        self::assertSame(2, $admission->quantity);
        self::assertSame('HMC1.adm.56666666.', substr((string) $admission->passCode(1_700_000_000), 0, 18));
        self::assertNull((new Admission(['id' => 'x']))->passCode());
        self::assertSame('COVER', (new Admission(['id' => 'x']))->kind);

        $cover = new VenueCover(['id' => 'v', 'name' => 'Bar', 'tickets' => ['cover' => [
            'charge' => ['payable' => true], 'viewerAdmission' => ['id' => 'a1'], 'viewerCoatCheck' => null,
        ]]]);
        self::assertTrue($cover->charge?->payable);
        self::assertSame('a1', $cover->viewerAdmission?->id);
        self::assertNull($cover->viewerCoatCheck);
    }

    public function testRsvp(): void
    {
        $rsvp = new EventRSVP(['count' => 3, 'mine' => 'ATTENDING', 'mineSource' => 'TICKET', 'counts' => ['going' => 3, 'interested' => 1, 'tickets' => 2],
            'attendees' => ['nodes' => [['profile' => ['id' => 'u', 'name' => 'Ada'], 'friend' => true], 'junk']]]);
        self::assertTrue($rsvp->isGoing());
        self::assertSame(2, $rsvp->tickets);
        self::assertSame('Ada', $rsvp->attendeeProfiles()[0]->name);
        self::assertFalse((new EventRSVP([]))->isGoing());
    }

    public function testSoapbox(): void
    {
        $article = new Article([
            'id' => 'a', 'title' => 'News', 'publishedAt' => '2026-11-24T12:00:00Z', 'teaser' => true, 'kind' => 'ARTICLE',
            'publication' => ['id' => 'p', 'name' => 'QSaltLake', 'trusted' => true],
            'body' => 'Body', 'venues' => [['id' => 'v', 'name' => 'Bar']], 'status' => 'PUBLISHED',
        ]);
        self::assertTrue($article->teaser);
        self::assertSame('QSaltLake', $article->publication?->name);
        self::assertTrue($article->publication?->trusted);
        self::assertSame(['venues' => [['id' => 'v', 'name' => 'Bar']]], $article->subjects);
        $publication = new Publication(['id' => 'p', 'acceptsOpEds' => true, 'adFreeOffered' => true, 'adFreeTipCents' => 300, 'locale' => ['id' => 'l']]);
        self::assertTrue($publication->acceptsOpEds);
        self::assertSame(300, $publication->adFreeTipCents);
        self::assertSame('l', $publication->locale?->id);

        $page = ArticlesPage::fromConnection(['nodes' => [['id' => 'a']], 'pageInfo' => ['endCursor' => 'c', 'hasNextPage' => true]]);
        self::assertSame('c', $page->endCursor);
        self::assertTrue($page->hasNextPage);
        $last = ArticlesPage::fromConnection(['nodes' => [], 'pageInfo' => ['endCursor' => 'c', 'hasNextPage' => false]]);
        self::assertNull($last->endCursor);
        self::assertSame([], ArticlesPage::fromConnection(null)->articles);
    }

    public function testCalendarFeed(): void
    {
        $feed = new CalendarFeed(['url' => 'https://api.audiencekit.com/cal/x.ics', 'venues' => [['id' => 'v1'], 'junk']]);
        self::assertSame('webcal://api.audiencekit.com/cal/x.ics', $feed->webcalUrl);
        self::assertSame('https://calendar.google.com/calendar/render?cid=webcal%3A%2F%2Fapi.audiencekit.com%2Fcal%2Fx.ics', $feed->googleUrl);
        self::assertTrue($feed->follows('v1'));
        self::assertFalse($feed->follows('v2'));
        $given = new CalendarFeed(['url' => 'u', 'webcalUrl' => 'w', 'googleUrl' => 'g']);
        self::assertSame(['w', 'g'], [$given->webcalUrl, $given->googleUrl]);
    }

    public function testPublicListings(): void
    {
        $page = PublicListingsPage::fromArray(['listings' => [
            ['kind' => 'venue', 'id' => 7, 'title' => 'Bar', 'visibility' => 'community', 'listed' => true],
            ['kind' => 'event', 'id' => 'e', 'start_at' => '2026-11-25T03:00:00Z', 'cover_cents' => '500', 'is_canceled' => false],
        ], 'page_count' => '2', 'next_page' => 2]);
        self::assertSame(2, $page->pageCount);
        self::assertSame(2, $page->nextPage);
        self::assertSame('7', $page->listings[0]->id);
        self::assertFalse($page->listings[0]->isPublic());
        self::assertTrue($page->listings[1]->isPublic());
        self::assertSame(500, $page->listings[1]->coverCents);
        self::assertSame('2026-11-25', $page->listings[1]->startAt?->format('Y-m-d'));
        self::assertNull(PublicListingsPage::fromArray([])->nextPage);
        self::assertSame('', (new PublicListing([]))->kind);
    }
}
