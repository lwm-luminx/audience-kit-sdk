<?php

declare(strict_types=1);

namespace AudienceKit\Tests;

use AudienceKit\AudienceKitException;
use AudienceKit\AudienceSession;
use AudienceKit\Configuration;
use AudienceKit\Coordinate;
use AudienceKit\DeviceDescription;
use AudienceKit\InMemoryCredentialStore;
use AudienceKit\Queries;
use AudienceKit\ReportTarget;
use AudienceKit\SchemaShape;
use InvalidArgumentException;
use Nyholm\Psr7\Factory\Psr17Factory;

/** The calls the PHP SDK has had since 0.2.0, in step with the Swift, Kotlin, Node and Python SDKs. */
final class ParityTest extends TestCase
{
    private const SERVICE_JSON = [
        'token' => 'service-session', 'audienceId' => self::AUDIENCE_ID, 'role' => 'service',
        'endpoint' => 'https://next.audiencekit.com/v1/audience/' . self::AUDIENCE_ID . '/graphql',
        'expiresAt' => '2099-01-01T00:00:00Z', 'scopes' => ['public:read'],
    ];

    // Sign-in

    public function testSignInWithGoogle(): void
    {
        $this->respond(self::SERVICE_JSON + ['userId' => 'u']);
        $session = $this->session(new Configuration(host: 'hotmess.social'));
        $credential = $session->signInWithGoogle('id-token', new DeviceDescription('server'), 'Ada', 'access');
        self::assertSame('u', $credential->userId);
        self::assertSame('/v1/token/google', $this->sent()->getUri()->getPath());
        self::assertSame(
            ['id_token' => 'id-token', 'access_token' => 'access', 'host' => 'hotmess.social',
             'device' => ['identifier' => 'server', 'type' => 'web'], 'name' => 'Ada'],
            $this->sentJson(),
        );
        self::assertFalse($this->sent()->hasHeader('Authorization'));
    }

    public function testConnectGoogleNeedsASession(): void
    {
        $this->respond(self::SERVICE_JSON + ['userId' => 'u']);
        $session = $this->signedIn();
        $session->connectGoogle('id-token', new DeviceDescription('server'));
        self::assertTrue($this->sentJson()['connect']);
        self::assertSame('Bearer secret-token', $this->sent()->getHeaderLine('Authorization'));

        $this->expectExceptionObject(AudienceKitException::notSignedIn());
        $this->session()->connectGoogle('id-token', new DeviceDescription('server'));
    }

    public function testSignInWithAppleOnTheWeb(): void
    {
        $this->respond(self::SERVICE_JSON + ['userId' => 'u']);
        $this->session()->signInWithApple('identity', new DeviceDescription('s'), 'code', 'https://site/callback', 'nonce', 'Ada');
        self::assertSame('/v1/token/apple', $this->sent()->getUri()->getPath());
        $json = $this->sentJson();
        self::assertSame(['identity', 'code', 'https://site/callback', 'nonce', 'Ada'], [
            $json['identity_token'], $json['authorization_code'], $json['redirect_uri'], $json['nonce'], $json['first_name'],
        ]);
        self::assertArrayNotHasKey('last_name', $json);
    }

    public function testSignInWithAReviewCode(): void
    {
        $this->respond(self::SERVICE_JSON + ['userId' => 'reviewer']);
        $this->respond(['error' => 'invalid_code'], 401);
        $session = $this->session();
        self::assertSame('reviewer', $session->signInWithReviewCode(' 123456 ', new DeviceDescription('s'))->userId);
        self::assertSame('123456', $this->sentJson()['code']);
        try {
            $session->signInWithReviewCode('000000', new DeviceDescription('s'));
            self::fail('Expected an exception.');
        } catch (AudienceKitException $error) {
            self::assertSame(AudienceKitException::CODE_SIGN_IN_REJECTED, $error->errorCode);
        }
    }

    public function testFacebookCodeForAnotherApp(): void
    {
        $this->respond(self::SERVICE_JSON + ['userId' => 'u']);
        $this->session(new Configuration(facebookAppId: 'configured'))
            ->signInWithFacebookCode('code', 'https://site/fb', new DeviceDescription('s'), 'business-app');
        self::assertSame('business-app', $this->sentJson()['facebook_app_id']);
    }

    public function testRefreshSession(): void
    {
        $this->respond(['token' => 'refreshed', 'userId' => 'user-1', 'role' => 'member', 'endpoint' => self::ENDPOINT]);
        $session = $this->signedIn();
        self::assertSame('refreshed', $session->refreshSession()->token);
        self::assertSame('/v1/token/refresh', $this->sent()->getUri()->getPath());
        self::assertSame('Bearer secret-token', $this->sent()->getHeaderLine('Authorization'));
        self::assertSame('refreshed', $session->sessionToken());
    }

    public function testDeleteAccount(): void
    {
        $this->respondData(['deleteAccount' => ['deleted' => false]]);
        $this->respondData(['deleteAccount' => ['deleted' => true]]);
        $session = $this->signedIn();
        self::assertFalse($session->deleteAccount());
        self::assertTrue($session->isSignedIn());
        self::assertSame(['confirm' => true], $this->sentJson()['variables']);
        self::assertTrue($session->deleteAccount());
        self::assertFalse($session->isSignedIn());
    }

    // Service tokens

    public function testAServiceTokenIsTradedAndFollowedToItsInstance(): void
    {
        $this->respond(self::SERVICE_JSON);
        $this->respondData(['id' => self::AUDIENCE_ID, 'name' => 'Hot Mess']);
        $session = $this->session();
        $credential = $session->useServiceToken('akst_abc_secret');
        self::assertTrue($credential->isService());
        self::assertSame('/v1/token/service', $this->sent()->getUri()->getPath());
        self::assertSame(['service_token' => 'akst_abc_secret'], $this->sentJson());
        self::assertFalse($this->sent()->hasHeader('Authorization'));

        self::assertSame('Hot Mess', $session->audience()->name);
        self::assertSame('next.audiencekit.com', $this->sent()->getUri()->getHost());
        self::assertSame('Bearer service-session', $this->sent()->getHeaderLine('Authorization'));
    }

    public function testAnExpiringServiceSessionIsRenewedFirst(): void
    {
        $expiring = ['expiresAt' => gmdate('Y-m-d\TH:i:s\Z', time() + 30)] + self::SERVICE_JSON;
        $this->respond($expiring);
        $this->respond(['token' => 'renewed'] + self::SERVICE_JSON);
        $this->respondData(['id' => 'a']);
        $session = $this->session();
        $session->useServiceToken('akst_abc_secret');
        $session->graphQL('query Audience { id }');
        self::assertCount(3, $this->http->getRequests());
        self::assertSame('/v1/token/service', $this->sent(1)->getUri()->getPath());
        self::assertSame('Bearer renewed', $this->sent()->getHeaderLine('Authorization'));
    }

    public function testARefusedServiceSessionIsTradedAgainOnce(): void
    {
        $this->respond(self::SERVICE_JSON);
        $this->respond(['error' => 'unauthorized'], 401);
        $this->respond(['token' => 'second'] + self::SERVICE_JSON);
        $this->respond(['listings' => [], 'page_count' => 1]);
        $this->respond(['error' => 'unauthorized'], 401);
        $this->respond(['token' => 'third'] + self::SERVICE_JSON);
        $this->respond(['error' => 'unauthorized'], 401);
        $session = $this->session();
        $session->useServiceToken('akst_abc_secret');

        self::assertSame([], $session->publicListingsPage()->listings);
        self::assertSame('Bearer second', $this->sent()->getHeaderLine('Authorization'));
        self::assertSame('next.audiencekit.com', $this->sent()->getUri()->getHost());

        try {
            $session->publicListingsPage();
            self::fail('Expected an exception.');
        } catch (AudienceKitException $error) {
            self::assertTrue($error->isUnauthenticated());
        }
        self::assertCount(7, $this->http->getRequests());
    }

    public function testARevokedServiceToken(): void
    {
        $this->respond(['error' => 'unauthorized'], 401);
        $this->respond(['error' => 'down'], 503);
        try {
            $this->session()->useServiceToken('akst_revoked');
            self::fail('Expected an exception.');
        } catch (AudienceKitException $error) {
            self::assertTrue($error->isUnauthenticated());
            self::assertStringContainsString('revoked', $error->getMessage());
        }
        $this->expectException(AudienceKitException::class);
        $this->session()->useServiceToken('akst_other');
    }

    public function testFromEnvironment(): void
    {
        $factory = new Psr17Factory();
        $this->respond(self::SERVICE_JSON);
        $this->respondData(['id' => 'a']);
        $session = AudienceSession::fromEnvironment([
            'AUDIENCEKIT_TOKEN' => 'akst_abc_secret', 'AUDIENCEKIT_BASE_URL' => 'https://next.audiencekit.com',
            'AUDIENCEKIT_HOST' => 'hotmess.social', 'AUDIENCEKIT_ENVIRONMENT' => 'staging', 'AUDIENCEKIT_AUDIENCE_ID' => '',
        ], $this->http, $factory, $factory);
        self::assertSame('https://next.audiencekit.com', $session->configuration->baseUrl);
        self::assertSame('hotmess.social', $session->configuration->host);
        self::assertNull($session->configuration->audienceId);
        $session->graphQL('query Audience { id }');
        self::assertSame('/v1/token/service', $this->sent(0)->getUri()->getPath(), 'traded on first use');
        self::assertSame('staging', $this->sent()->getHeaderLine('X-AudienceKit-Environment'));

        $bearer = AudienceSession::fromEnvironment(['AUDIENCEKIT_TOKEN' => 'app-key', 'AUDIENCEKIT_AUDIENCE_ID' => self::AUDIENCE_ID], $this->http, $factory, $factory);
        self::assertSame('bearer', $bearer->credential()?->role);
        $this->respondData(['id' => 'a']);
        $bearer->graphQL('query Audience { id }');
        self::assertSame('Bearer app-key', $this->sent()->getHeaderLine('Authorization'));
        self::assertSame('api.audiencekit.com', $this->sent()->getUri()->getHost());

        self::assertFalse(AudienceSession::fromEnvironment([], $this->http, $factory, $factory)->isSignedIn());
    }

    public function testSignOutForgetsTheServiceToken(): void
    {
        $this->respond(self::SERVICE_JSON);
        $this->respond('', 204);
        $session = $this->session();
        $session->useServiceToken('akst_abc_secret');
        $session->signOut();
        self::assertFalse($session->isSignedIn());
        $this->expectExceptionObject(AudienceKitException::notSignedIn());
        $session->request(new \AudienceKit\ApiRequest('/v1/public/listings'));
    }

    // RSVP, cover, location

    public function testRsvps(): void
    {
        $this->respondData(['cancelRsvp' => ['event' => ['id' => 'e1', 'rsvp' => ['count' => 4, 'mine' => null, 'mineSource' => null]]]]);
        $this->respondData(['cancelRsvp' => ['event' => null]]);
        $this->respondData(['events' => ['event' => ['id' => 'e1', 'rsvp' => ['count' => 5, 'mine' => 'ATTENDING', 'attendees' => ['nodes' => [['profile' => ['id' => 'u']]]]]]]]);
        $this->respondData(['events' => ['event' => null]]);
        $session = $this->signedIn();
        self::assertSame(4, $session->cancelRsvp('e1')->count);
        self::assertSame(['eventId' => 'e1'], $this->sentJson()['variables']);
        try {
            $session->cancelRsvp('e1');
            self::fail('Expected an exception.');
        } catch (AudienceKitException $error) {
            self::assertSame(AudienceKitException::CODE_DECODING, $error->errorCode);
        }
        $rsvp = $session->eventRsvp('e1', 10);
        self::assertTrue($rsvp?->isGoing());
        self::assertSame('u', $rsvp?->attendeeProfiles()[0]->id);
        self::assertSame(['id' => 'e1', 'first' => 10], $this->sentJson()['variables']);
        self::assertNull($session->eventRsvp('e2'));
    }

    public function testCoverOnASlidingScaleAndCoatCheck(): void
    {
        $this->respondData(['buyCover' => ['admission' => ['id' => 'a', 'status' => 'PENDING'], 'provider' => 'SQUARE', 'squareLocationId' => 'loc']]);
        $this->respondData(['buyCoatCheck' => ['admission' => ['id' => 'c', 'kind' => 'COAT_CHECK', 'quantity' => 2], 'provider' => 'STRIPE']]);
        $session = $this->signedIn();
        $purchase = $session->buyCover('v1', 1500);
        self::assertSame('loc', $purchase->squareLocationId);
        self::assertSame('a', $purchase->admission?->id);
        self::assertSame(['venueId' => 'v1', 'amount' => ['cents' => 1500, 'currency' => 'usd']], $this->sentJson()['variables']);
        $coats = $session->buyCoatCheck('v1', 2);
        self::assertSame(2, $coats->admission?->quantity);
        self::assertSame(['venueId' => 'v1', 'quantity' => 2], $this->sentJson()['variables']);
        self::assertStringContainsString('viewerCoatCheck', Queries::venueCover(SchemaShape::everything()));
    }

    public function testLocation(): void
    {
        $this->respondData(['closestLocale' => ['id' => 'l1', 'name' => 'Salt Lake']]);
        $this->respondData(['reportLocation' => ['venue' => ['id' => 'v1'], 'locale' => null]]);
        $session = $this->signedIn();
        self::assertSame('Salt Lake', $session->closestLocale(new Coordinate(40.76, -111.89, 5))?->name);
        self::assertSame(['near' => ['latitude' => 40.76, 'longitude' => -111.89, 'beaconMajor' => 5]], $this->sentJson()['variables']);
        $where = $session->reportLocation(new Coordinate(40.76, -111.89), 'venue { id } locale { id }');
        self::assertSame('v1', $where['venue']['id']);
        self::assertStringContainsString('reportLocation(input: { position: $position }) { venue { id } locale { id } }', $this->sentQuery());
    }

    public function testCommunity(): void
    {
        $undefined = [['message' => "Field 'people' doesn't exist", 'extensions' => ['code' => 'undefinedField']]];
        $this->respondData(['id' => 'a', 'name' => 'Hot Mess']);
        $this->respondData(['locales' => [['id' => 'l']]]);
        $this->respondData(['venues' => ['list' => ['nodes' => [['id' => 'v']]]]]);
        $this->respondErrors($undefined);
        $this->respondData(array_fill_keys(['t0', 't1', 't2', 't3', 't4', 't5'], null));
        $this->respondErrors($undefined);
        $this->respondData(['events' => ['list' => ['nodes' => [['id' => 'e']]]]]);
        $this->respondData(['events' => ['series' => ['nodes' => []]]]);
        $community = $this->signedIn()->community();
        self::assertSame('Hot Mess', $community->audience?->name);
        self::assertSame('l', $community->locales[0]->id);
        self::assertSame('v', $community->venues[0]->id);
        self::assertSame([], $community->people);
        self::assertSame('e', $community->events[0]->id);
        self::assertSame([], $community->eventSeries);
    }

    public function testCommunityPassesOtherErrorsOn(): void
    {
        $this->respondErrors([['message' => 'No', 'extensions' => ['code' => 'FORBIDDEN']]]);
        $this->expectException(AudienceKitException::class);
        $this->signedIn()->community();
    }

    // Soapbox

    public function testArticles(): void
    {
        $this->respondData(['soapbox' => ['articles' => ['nodes' => [['id' => 'a1', 'title' => 'News']]]]]);
        $this->respondData(['soapbox' => ['articles' => ['nodes' => [['id' => 'a2']], 'pageInfo' => ['endCursor' => 'c2', 'hasNextPage' => true]]]]);
        $this->respondData(['soapbox' => ['articles' => ['nodes' => [['id' => 'a3', 'featuredNationally' => true]]]]]);
        $this->respondData(['soapbox' => ['article' => ['id' => 'a1', 'body' => 'Body', 'people' => [['id' => 'p']]]]]);
        $this->respondData(['soapbox' => null]);
        $session = $this->signedIn();

        self::assertSame('News', $session->articles('l1', first: 5)[0]->title);
        self::assertSame(['localeId' => 'l1', 'first' => 5], $this->sentJson()['variables']);
        self::assertStringContainsString('viewerAdFree', $this->sentQuery());

        $page = $session->articlesPage(publicationId: 'p1', after: 'c1');
        self::assertSame('c2', $page->endCursor);
        self::assertSame(['publicationId' => 'p1', 'first' => 20, 'after' => 'c1'], $this->sentJson()['variables']);

        self::assertTrue($session->nationalArticles()[0]->featuredNationally);
        self::assertArrayNotHasKey('variables', $this->sentJson());

        $article = $session->article('a1');
        self::assertSame('Body', $article?->body);
        self::assertSame(['people' => [['id' => 'p']]], $article?->subjects);
        self::assertStringContainsString('body venues { id name } events { id name }', $this->sentQuery());
        self::assertNull($session->article('gone'));
    }

    public function testArticlesAbout(): void
    {
        $this->respondData(['venues' => ['venue' => ['articles' => ['list' => ['nodes' => [['id' => 'a1']]]]]]]);
        $this->respondData(['locale' => ['articles' => ['list' => ['nodes' => [['id' => 'a2']]]]]]);
        $this->respondData(['people' => ['person' => null]]);
        $session = $this->signedIn();
        self::assertSame('a1', $session->articlesAbout('venue', 'v1', 3)[0]->id);
        self::assertSame(['id' => 'v1', 'first' => 3], $this->sentJson()['variables']);
        self::assertStringContainsString('venues { venue(id: $id) { articles { list(first: $first)', $this->sentQuery());
        self::assertSame('a2', $session->articlesAbout('locale', 'l1')[0]->id);
        self::assertSame([], $session->articlesAbout('person', 'p1'));
        self::assertStringContainsString('events { event(id: $id)', Queries::articlesAbout('event')[1](SchemaShape::everything()));
        self::assertSame('query ArticlesAbout { id }', Queries::articlesAbout('event')[1](new SchemaShape(['Event' => ['id']])));
        $this->expectException(InvalidArgumentException::class);
        $session->articlesAbout('post', 'x');
    }

    public function testPublicationsAndOpEds(): void
    {
        $this->respondData(['soapbox' => ['publications' => [['id' => 'p1', 'locale' => ['id' => 'L1']], ['id' => 'p2', 'locale' => null]]]]);
        $this->respondData(['soapbox' => ['publications' => [['id' => 'p1', 'locale' => ['id' => 'L1']], ['id' => 'p2']]]]);
        $this->respondData(['soapbox' => ['publication' => ['id' => 'p1', 'acceptsOpEds' => true]]]);
        $this->respondData(['soapbox' => ['myOpEds' => [['id' => 'o1', 'status' => 'SUBMITTED']]]]);
        $this->respondData(['submitOpEd' => ['article' => ['id' => 'o2', 'status' => 'SUBMITTED']]]);
        $session = $this->signedIn();
        self::assertCount(2, $session->publications());
        self::assertSame(['p1'], array_map(static fn ($p) => $p->id, $session->localPublications('l1')));
        self::assertTrue($session->publication('p1')?->acceptsOpEds);
        self::assertSame('SUBMITTED', $session->myOpEds()[0]->status);
        self::assertSame('o2', $session->submitOpEd('p1', 'Title', 'Body', byline: 'A reader')->id);
        self::assertSame(
            ['publicationId' => 'p1', 'title' => 'Title', 'body' => 'Body', 'summary' => null, 'byline' => 'A reader'],
            $this->sentJson()['variables'],
        );
    }

    public function testWithoutSoapbox(): void
    {
        $none = new SchemaShape(['Audience' => ['id']]);
        foreach (['articles', 'articlesPage', 'nationalArticles', 'article', 'publications', 'publication', 'myOpEds'] as $name) {
            self::assertSame('query ' . ucfirst($name) . ' { id }', Queries::$name($none), $name);
        }
        self::assertStringNotContainsString('viewerAdFree', Queries::articleFields($none));
        self::assertStringNotContainsString('adFreeOffered', Queries::publicationFields($none));
        $this->respondData(['id' => 'a']);
        self::assertSame([], $this->signedIn()->articlesPage()->articles);
    }

    // Calendar and moderation

    public function testCalendar(): void
    {
        $feed = ['url' => 'https://api.audiencekit.com/c.ics', 'webcalUrl' => 'webcal://api.audiencekit.com/c.ics', 'googleUrl' => 'g', 'venues' => [['id' => 'v1']]];
        $this->respondData(['me' => ['calendarFeed' => null]]);
        $this->respondData(['createCalendarFeed' => ['calendarFeed' => $feed]]);
        $this->respondData(['setCalendarFeedVenue' => ['calendarFeed' => $feed]]);
        $this->respondData(['deleteCalendarFeed' => ['deleted' => true]]);
        $session = $this->signedIn();
        self::assertNull($session->calendarFeed());
        self::assertSame('g', $session->createCalendarFeed(true)->googleUrl);
        self::assertSame(['reset' => true], $this->sentJson()['variables']);
        self::assertTrue($session->followVenueInCalendar('v1')->follows('v1'));
        self::assertSame(['venueId' => 'v1', 'following' => true], $this->sentJson()['variables']);
        self::assertTrue($session->deleteCalendarFeed());
    }

    public function testModeration(): void
    {
        $this->respondData(['reportContent' => ['reported' => true, 'blocked' => true]]);
        $this->respondData(['reportContent' => null]);
        $this->respondData(['blockUser' => ['blockedUsers' => [['id' => 'u2']]]]);
        $this->respondData(['unblockUser' => ['blockedUsers' => []]]);
        $session = $this->signedIn();
        $result = $session->reportContent(ReportTarget::MESSAGE, 'm1', ReportTarget::INTIMATE_IMAGE, true);
        self::assertTrue($result->reported && $result->blocked);
        self::assertSame(
            ['targetType' => 'MESSAGE', 'targetId' => 'm1', 'reason' => ReportTarget::INTIMATE_IMAGE, 'block' => true],
            $this->sentJson()['variables'],
        );
        self::assertFalse($session->reportContent(ReportTarget::PERSON, 'u2')->reported);
        $session->blockUser('u2');
        self::assertSame(['userId' => 'u2'], $this->sentJson()['variables']);
        $session->unblockUser('u2');
        self::assertSame('UnblockUser', $this->sentJson()['operationName']);
        self::assertContains(ReportTarget::INTIMATE_IMAGE, ReportTarget::REASONS);
    }

    // Public listings

    public function testPublicListings(): void
    {
        $this->respond(['listings' => [['kind' => 'venue', 'id' => 'v1']], 'page_count' => 2, 'next_page' => 2]);
        $this->respond(['listings' => [['kind' => 'event', 'id' => 'e1']], 'page_count' => 2, 'next_page' => null]);
        $this->respond(['kind' => 'venue', 'id' => 'v1', 'title' => 'Bar']);
        $this->respond(['error' => 'not_found'], 404);
        $this->respond(['error' => 'forbidden', 'message' => 'Needs public:read'], 403);
        $this->respond(['venue' => ['id' => 'v1'], 'now' => null]);
        $session = $this->signedIn();

        self::assertSame(['v1', 'e1'], array_map(static fn ($l) => $l->id, $session->publicListings()));
        self::assertSame('page=2', $this->sent()->getUri()->getQuery());
        self::assertSame('Bar', $session->publicListing('venue', 'v1')?->title);
        self::assertSame('/v1/public/venues/v1', $this->sent()->getUri()->getPath());
        self::assertNull($session->publicListing('event', 'gone'));
        try {
            $session->publicListing('post', 'p1');
            self::fail('Expected an exception.');
        } catch (AudienceKitException $error) {
            self::assertSame(AudienceKitException::CODE_FORBIDDEN, $error->errorCode);
        }
        self::assertSame('v1', $session->publicTonight('v1')['venue']['id']);
        self::assertSame('/v1/public/venues/v1/tonight', $this->sent()->getUri()->getPath());
        $this->expectException(InvalidArgumentException::class);
        $session->publicListing('person', 'x');
    }

    public function testChatRoomDocuments(): void
    {
        self::assertStringContainsString('room: venueChat(venueId: $id) {', Queries::chatRoom('venue'));
        self::assertStringContainsString('room: localeChat(localeId: $id, watch: true) {', Queries::chatRoom('locale', true));
        self::assertStringEndsWith('fragment Line on ChatMessage { ' . Queries::CHAT_MESSAGE_FIELDS . ' }', Queries::chatRoom('venue'));
    }

    public function testJockeysNeedTheirApi(): void
    {
        self::assertStringContainsString('jockeyLabel', Queries::eventFields(SchemaShape::everything()));
        $older = new SchemaShape(['Event' => ['id', 'people'], 'EventPeopleView' => ['hosts', 'lineup']]);
        self::assertStringNotContainsString('jockeys', Queries::eventFields($older));
    }

    public function testTheStoreIsTheOneGiven(): void
    {
        $store = new InMemoryCredentialStore();
        $this->respond(self::SERVICE_JSON);
        $this->session(null, $store)->useServiceToken('akst_x');
        self::assertSame('service-session', $store->load()?->token);
    }
}
