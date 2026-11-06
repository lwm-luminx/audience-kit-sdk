<?php

declare(strict_types=1);

namespace AudienceKit\Tests;

use AudienceKit\AudienceKitException;
use AudienceKit\Queries;
use AudienceKit\SchemaShape;

final class OperationsTest extends TestCase
{
    private const UNDEFINED = [['message' => "Field 'profile' doesn't exist on type 'Venue'", 'extensions' => ['code' => 'undefinedField']]];

    public function testAudienceAndMe(): void
    {
        $this->respondData(['id' => 'a', 'name' => 'Hot Mess', 'subdomain' => 'hotmess']);
        $this->respondData(['me' => ['self' => ['id' => 'u', 'name' => 'Ada']]]);
        $this->respondData(['me' => null]);
        $session = $this->signedIn();
        self::assertSame('Hot Mess', $session->audience()['name']);
        self::assertSame('Ada', $session->me()['name']);
        self::assertNull($session->me());
        self::assertSame(Queries::AUDIENCE, $this->sentQuery(0));
    }

    public function testVenuesAskForEverythingFirst(): void
    {
        $this->respondData(['venues' => ['list' => ['nodes' => [['id' => 'v1', 'name' => 'Bar'], 'junk']]]]);
        $venues = $this->signedIn()->venues();
        self::assertSame([['id' => 'v1', 'name' => 'Bar']], $venues);
        $query = $this->sentQuery();
        self::assertStringContainsString('profile { facebook { page { id name photoUrl bannerUrl } } }', $query);
        self::assertStringContainsString('places { placeId }', $query);
        self::assertSame('Venues', $this->sentJson()['operationName']);
    }

    public function testVenuesFollowTheAudiencesModules(): void
    {
        $this->respondErrors(self::UNDEFINED);
        $this->respondData([
            't0' => ['fields' => [['name' => 'id']]],              // Event
            't1' => null,                                          // ListingProfile
            't2' => ['fields' => [['name' => 'id'], ['name' => 'name'], ['name' => 'label'], ['name' => 'cityNames'], ['name' => 'bannerUrl']]], // Locale
            't3' => ['fields' => [['name' => 'id'], ['name' => 'point'], ['name' => 'address']]], // Location
            't4' => ['fields' => [['name' => 'id']]],              // Person
            't5' => ['fields' => [['name' => 'id'], ['name' => 'name'], ['name' => 'locale'], ['name' => 'location'], ['name' => 'tags']]], // Venue
        ]);
        $this->respondData(['venues' => ['list' => ['nodes' => [['id' => 'v1']]]]]);
        $this->respondData(['venues' => ['list' => ['nodes' => []]]]);
        $session = $this->signedIn();

        self::assertSame([['id' => 'v1']], $session->venues());
        self::assertCount(3, $this->http->getRequests());
        $shaped = $this->sentQuery(2);
        self::assertStringNotContainsString('profile', $shaped);
        self::assertStringNotContainsString('places', $shaped);
        self::assertStringContainsString('location { id point address }', $shaped);

        // The shape is remembered: the next call goes straight to the right document.
        self::assertSame([], $session->venues());
        self::assertCount(4, $this->http->getRequests());
        self::assertSame($shaped, $this->sentQuery(3));
    }

    public function testOtherGraphQLErrorsAreNotRetried(): void
    {
        $this->respondErrors([['message' => 'Nope', 'extensions' => ['code' => 'FORBIDDEN']]]);
        try {
            $this->signedIn()->venues();
            self::fail('Expected an exception.');
        } catch (AudienceKitException $error) {
            self::assertSame('FORBIDDEN', $error->errorCode);
        }
        self::assertCount(1, $this->http->getRequests());
    }

    public function testVenuesWithoutTheModule(): void
    {
        $this->respondData(['venues' => null]);
        self::assertSame([], $this->signedIn()->venues());
    }

    public function testPeopleAndLocales(): void
    {
        $this->respondData(['people' => ['list' => ['nodes' => [['id' => 'p1']]]]]);
        $this->respondData(['locales' => [['id' => 'l1'], null]]);
        $this->respondData(['locales' => null]);
        $this->respondData(['closestLocale' => ['id' => 'l1']]);
        $this->respondData(['closestLocale' => null]);
        $session = $this->signedIn();
        self::assertSame([['id' => 'p1']], $session->people());
        self::assertStringContainsString('involvements { edges { relationship role via { id name } node {', $this->sentQuery());
        self::assertSame([['id' => 'l1']], $session->locales());
        self::assertSame([], $session->locales());
        self::assertSame(['id' => 'l1'], $session->closestLocale(37.78, -122.41));
        self::assertSame(['near' => ['latitude' => 37.78, 'longitude' => -122.41]], $this->sentJson()['variables']);
        self::assertNull($session->closestLocale(0, 0));
    }

    public function testEvents(): void
    {
        $this->respondData(['events' => ['list' => ['nodes' => [['id' => 'e1']]]]]);
        $this->respondData(['events' => ['event' => ['id' => 'e1', 'name' => 'Night']]]);
        $this->respondData(['events' => ['event' => null]]);
        $this->respondData(['events' => ['series' => ['nodes' => [['id' => 's1']]]]]);
        $this->respondData(['events' => null]);
        $session = $this->signedIn();

        self::assertSame([['id' => 'e1']], $session->events('PAST', 'l1', 'v1', 10));
        self::assertSame(['window' => 'PAST', 'first' => 10, 'localeId' => 'l1', 'venueId' => 'v1'], $this->sentJson()['variables']);
        self::assertStringContainsString('rsvp { mine count }', $this->sentQuery());
        self::assertStringContainsString('tickets { url offers { nodes {', $this->sentQuery());
        self::assertSame('Night', $session->event('e1')['name']);
        self::assertSame(['id' => 'e1'], $this->sentJson()['variables']);
        self::assertNull($session->event('e2'));
        self::assertSame([['id' => 's1']], $session->eventSeries(venueId: 'v1'));
        self::assertSame(['first' => 100, 'venueId' => 'v1'], $this->sentJson()['variables']);
        self::assertStringContainsString('recurrenceText startsOn startTime timeZone', $this->sentQuery());
        self::assertSame([], $session->eventSeries(localeId: 'l1'));
        self::assertSame(['first' => 100, 'localeId' => 'l1'], $this->sentJson()['variables']);
    }

    public function testVenueDetail(): void
    {
        $this->respondData(['venues' => ['venue' => ['id' => 'v1', 'chat' => ['open' => true]]]]);
        $this->respondData(['venues' => ['venue' => null]]);
        $session = $this->signedIn();
        self::assertTrue($session->venueDetail('v1', 5)['chat']['open']);
        self::assertSame(['id' => 'v1', 'recentMessages' => 5], $this->sentJson()['variables']);
        self::assertStringContainsString('query VenueDetail($id: ID!, $recentMessages: Int)', $this->sentQuery());
        self::assertStringContainsString('recentMessages(limit: $recentMessages)', $this->sentQuery());
        self::assertStringContainsString('socialLinks { nodes { id handle provider url } }', $this->sentQuery());
        self::assertStringContainsString('events { upcoming(first: 20)', $this->sentQuery());
        self::assertNull($session->venueDetail('v2'));
    }

    public function testVenueDetailWithoutChatLeavesTheVariableOut(): void
    {
        $shape = new SchemaShape(['Venue' => ['id', 'name', 'profile']]);
        $document = Queries::venueDetail($shape);
        self::assertStringContainsString('query VenueDetail($id: ID!) {', $document);
        self::assertStringNotContainsString('$recentMessages', $document);
        self::assertStringNotContainsString('events {', $document);
        self::assertStringContainsString('profile { address phone website', $document);
    }

    public function testCover(): void
    {
        $this->respondData(['venues' => ['venue' => ['id' => 'v1', 'tickets' => ['cover' => ['charge' => null]]]]]);
        $this->respondData(['venues' => ['venue' => null]]);
        $this->respondData(['venues' => ['venue' => ['id' => 'v1', 'tickets' => ['offers' => ['nodes' => [['url' => 'x']]]]]]]);
        $this->respondData(['venues' => ['venue' => ['id' => 'v1']]]);
        $this->respondData(['me' => ['cover' => ['admissions' => ['nodes' => [['id' => 'adm']]]]]]);
        $this->respondData(['buyCover' => ['admission' => ['id' => 'adm'], 'provider' => 'stripe']]);
        $this->respondData(['payCover' => ['admission' => ['id' => 'adm', 'status' => 'paid']]]);
        $this->respondData(['confirmCover' => ['admission' => ['id' => 'adm', 'status' => 'confirmed']]]);
        $this->respondData(['refundAdmission' => ['admission' => ['id' => 'adm', 'status' => 'refunded']]]);
        $session = $this->signedIn();

        self::assertSame('v1', $session->venueCover('v1')['id']);
        self::assertStringContainsString('viewerAdmission { ' . Queries::ADMISSION_FIELDS, $this->sentQuery());
        self::assertNull($session->venueCover('v2'));
        self::assertSame([['url' => 'x']], $session->venueOffers('v1', '2026-11-06'));
        self::assertSame(['id' => 'v1', 'night' => '2026-11-06'], $this->sentJson()['variables']);
        self::assertStringContainsString('query VenueOffers($id: ID!, $night: ISO8601Date)', $this->sentQuery());
        self::assertSame([], $session->venueOffers('v1'));
        self::assertSame(['id' => 'v1'], $this->sentJson()['variables']);
        self::assertSame([['id' => 'adm']], $session->admissions());
        self::assertSame('stripe', $session->buyCover('v1')['provider']);
        self::assertSame(['venueId' => 'v1'], $this->sentJson()['variables']);
        self::assertSame('paid', $session->payCover('adm', 'src', 'verify')['status']);
        self::assertSame(['admissionId' => 'adm', 'sourceId' => 'src', 'verificationToken' => 'verify'], $this->sentJson()['variables']);
        self::assertSame('confirmed', $session->confirmCover('adm')['status']);
        self::assertSame('refunded', $session->refundAdmission('adm')['status']);
    }

    public function testVenueOffersWithoutTicketing(): void
    {
        $document = Queries::venueOffers(new SchemaShape(['Venue' => ['id']]));
        self::assertSame("query VenueOffers(\$id: ID!) {\n  venues { venue(id: \$id) { id } }\n}", $document);
        self::assertStringNotContainsString('tickets', Queries::venueCover(new SchemaShape(['Venue' => ['id']])));
    }

    public function testPayCoverWithoutAVerificationToken(): void
    {
        $this->respondData(['payCover' => ['admission' => ['id' => 'adm']]]);
        $this->signedIn()->payCover('adm', 'src');
        self::assertSame(['admissionId' => 'adm', 'sourceId' => 'src'], $this->sentJson()['variables']);
    }

    public function testAMissingPayloadIsADecodingError(): void
    {
        $this->respondData(['buyCover' => null]);
        try {
            $this->signedIn()->buyCover('v1');
            self::fail('Expected an exception.');
        } catch (AudienceKitException $error) {
            self::assertSame(AudienceKitException::CODE_DECODING, $error->errorCode);
            self::assertStringContainsString('no buyCover', $error->getMessage());
        }
    }

    public function testRsvp(): void
    {
        $this->respondData(['rsvpEvent' => ['event' => ['id' => 'e1', 'rsvp' => ['mine' => 'ATTENDING']]]]);
        $this->respondData(['rsvpEvent' => ['event' => ['id' => 'e1']]]);
        $session = $this->signedIn();
        self::assertSame('ATTENDING', $session->rsvpEvent('e1', 'ATTENDING'));
        self::assertSame(['eventId' => 'e1', 'state' => 'ATTENDING'], $this->sentJson()['variables']);
        $this->expectExceptionMessage('no answer');
        $session->rsvpEvent('e1', 'MAYBE');
    }

    public function testTribes(): void
    {
        $this->respondData([
            'id' => 'a',
            'tribes' => [['id' => 't1', 'name' => 'Bears']],
            'me' => ['self' => ['id' => 'u', 'tribes' => [['isPrivate' => false, 'tag' => ['id' => 't1']]]]],
        ]);
        $this->respondData(['tribes' => null, 'me' => null]);
        $this->respondData(['identifyWithTribe' => ['tribes' => [['isPrivate' => true, 'tag' => ['id' => 't2']]]]]);
        $this->respondData(['leaveTribe' => ['tribes' => []]]);
        $session = $this->signedIn();

        $tribes = $session->tribes();
        self::assertSame('Bears', $tribes['tribes'][0]['name']);
        self::assertSame('t1', $tribes['mine'][0]['tag']['id']);
        self::assertSame(['tribes' => [], 'mine' => []], $session->tribes());
        self::assertTrue($session->identifyWithTribe('t2', true)[0]['isPrivate']);
        self::assertSame(['tagId' => 't2', 'isPrivate' => true], $this->sentJson()['variables']);
        self::assertSame([], $session->leaveTribe('t2'));
        self::assertSame(['tagId' => 't2'], $this->sentJson()['variables']);
    }

    public function testIdentifyWithTribeWithoutPrivacy(): void
    {
        $this->respondData(['identifyWithTribe' => ['tribes' => []]]);
        $this->signedIn()->identifyWithTribe('t2');
        self::assertSame(['tagId' => 't2'], $this->sentJson()['variables']);
    }

    public function testRegisterDeviceAndNode(): void
    {
        $this->respondData(['registerDevice' => ['registered' => true]]);
        $this->respondData(['registerDevice' => null]);
        $this->respondData(['node' => ['__typename' => 'Venue', 'id' => 'v1']]);
        $this->respondData(['node' => null]);
        $session = $this->signedIn();
        self::assertTrue($session->registerDevice('apns', 'social.hotmess', true));
        self::assertSame(['notificationToken' => 'apns', 'appId' => 'social.hotmess', 'sandbox' => true], $this->sentJson()['variables']);
        self::assertFalse($session->registerDevice('apns'));
        self::assertSame(['notificationToken' => 'apns'], $this->sentJson()['variables']);
        self::assertSame('Venue', $session->nodeType('v1'));
        self::assertNull($session->nodeType('x'));
    }

    public function testChat(): void
    {
        $this->respondData(['sendMyChatMessage' => ['message' => ['id' => 'm1', 'message' => 'hi']]]);
        $this->respondData(['removeMyChatMessage' => ['deletedId' => 'm1']]);
        $this->respondData(['removeMyChatMessage' => null]);
        $session = $this->signedIn();
        self::assertSame('m1', $session->sendChatMessage('hi', ['venueId' => 'v1'], 'prompt-1')['id']);
        self::assertSame(
            ['input' => ['venueId' => 'v1', 'message' => 'hi', 'promptId' => 'prompt-1']],
            $this->sentJson()['variables'],
        );
        self::assertSame('m1', $session->removeChatMessage('m1'));
        self::assertSame('m2', $session->removeChatMessage('m2'));
    }

    public function testEveryDocumentParsesAsAnOperation(): void
    {
        $documents = Queries::all();
        self::assertCount(25, $documents);
        foreach ($documents as $name => $document) {
            self::assertMatchesRegularExpression('/^\s*(query|mutation) ' . $name . '\b/', $document, $name);
            self::assertSame(substr_count($document, '{'), substr_count($document, '}'), "$name has unbalanced braces");
        }
    }

    public function testSchemaShape(): void
    {
        self::assertTrue(SchemaShape::everything()->has('Any', 'thing'));
        $shape = new SchemaShape(['Venue' => ['id']]);
        self::assertTrue($shape->has('Venue', 'id'));
        self::assertFalse($shape->has('Venue', 'chat'));
        self::assertFalse($shape->has('Person', 'id'));
    }
}
