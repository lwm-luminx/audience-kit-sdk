<?php

declare(strict_types=1);

namespace AudienceKit\Tests;

use AudienceKit\ApiRequest;
use AudienceKit\AudienceKit;
use AudienceKit\AudienceKitException;
use AudienceKit\AudienceSession;
use AudienceKit\Configuration;
use AudienceKit\Credential;
use AudienceKit\CredentialStore;
use AudienceKit\DeviceDescription;
use AudienceKit\Environment;
use AudienceKit\InMemoryCredentialStore;
use Http\Client\Exception\TransferException;
use RuntimeException;

final class SessionTest extends TestCase
{
    private const CREDENTIAL_JSON = [
        'token' => 'new-token', 'userId' => 'user-2', 'audienceId' => self::AUDIENCE_ID, 'role' => 'member',
        'endpoint' => self::ENDPOINT, 'venueDeviceId' => null, 'expiresAt' => null,
    ];

    // Headers and transport

    public function testEveryCallCarriesTheSdkHeaders(): void
    {
        $this->respondData(['id' => self::AUDIENCE_ID]);
        $session = $this->signedIn(new Configuration(environment: Environment::STAGING));
        $session->graphQL('query Audience { id }');

        $request = $this->sent();
        self::assertSame('POST', $request->getMethod());
        self::assertSame('https://api.audiencekit.com/v1/audience/' . self::AUDIENCE_ID . '/graphql', (string) $request->getUri());
        self::assertSame(AudienceKit::clientHeader(), $request->getHeaderLine(AudienceKit::CLIENT_HEADER));
        self::assertSame(AudienceKit::API_VERSION, $request->getHeaderLine(AudienceKit::API_VERSION_HEADER));
        self::assertSame('staging', $request->getHeaderLine(Environment::HEADER));
        self::assertSame('Bearer secret-token', $request->getHeaderLine('Authorization'));
        self::assertSame('application/json', $request->getHeaderLine('Content-Type'));
        self::assertSame('application/json', $request->getHeaderLine('Accept'));
        self::assertSame('query', $request->getHeaderLine('X-APOLLO-OPERATION-TYPE'));
        self::assertSame('Audience', $request->getHeaderLine('X-APOLLO-OPERATION-NAME'));
    }

    public function testProductionLeavesTheEnvironmentHeaderOut(): void
    {
        $this->respondData(['id' => '1']);
        $this->signedIn()->graphQL('{ id }');
        self::assertFalse($this->sent()->hasHeader(Environment::HEADER));
        self::assertSame('query', $this->sent()->getHeaderLine('X-APOLLO-OPERATION-TYPE'));
        self::assertFalse($this->sent()->hasHeader('X-APOLLO-OPERATION-NAME'));
    }

    public function testDescribe(): void
    {
        self::assertSame(['mutation', 'Buy'], AudienceSession::describe("  mutation Buy(\$id: ID!) { x }", null));
        self::assertSame(['mutation', 'Given'], AudienceSession::describe('mutation Buy { x }', 'Given'));
        self::assertSame(['subscription', null], AudienceSession::describe('subscription { x }', null));
        self::assertSame(['query', null], AudienceSession::describe('{ x }', null));
        self::assertSame(['query', 'N'], AudienceSession::describe('{ x }', 'N'));
    }

    public function testGraphQLSendsVariablesAndOperationName(): void
    {
        $this->respondData(['node' => ['__typename' => 'Venue', 'id' => 'v1']]);
        $data = $this->signedIn()->graphQL('query Node($id: ID!) { node(id: $id) { __typename id } }', ['id' => 'v1'], 'Node');
        self::assertSame('Venue', $data['node']['__typename']);
        $json = $this->sentJson();
        self::assertSame(['id' => 'v1'], $json['variables']);
        self::assertSame('Node', $json['operationName']);
        self::assertArrayHasKey('query', $json);
    }

    public function testGraphQLGoesToTheCredentialsInstance(): void
    {
        $this->respondData(['id' => '1']);
        $configuration = new Configuration(baseUrl: 'https://next.audiencekit.com');
        $credential = $this->credential(endpoint: 'http://localhost:3000/v1/audience/' . self::AUDIENCE_ID . '/graphql');
        $this->signedIn($configuration, $credential)->graphQL('{ id }');
        self::assertStringStartsWith('http://localhost:3000/v1/audience/', (string) $this->sent()->getUri());
    }

    public function testGraphQLNeedsASession(): void
    {
        try {
            $this->session(new Configuration(baseUrl: 'http://localhost:3000/', audienceId: 'aud'))->graphQL('{ id }');
            self::fail('Expected an exception.');
        } catch (AudienceKitException $error) {
            self::assertSame(AudienceKitException::CODE_NOT_SIGNED_IN, $error->errorCode);
        }
        self::assertCount(0, $this->http->getRequests());
    }

    public function testGraphQLUsesTheConfiguredAudienceForAPlatformSession(): void
    {
        $this->respondData(['id' => '1']);
        $configuration = new Configuration(baseUrl: 'http://localhost:3000/', audienceId: 'aud');
        $credential = $this->credential(audienceId: null, endpoint: 'http://localhost:3000/v1/admin/graphql');
        $this->signedIn($configuration, $credential)->graphQL('{ id }');
        self::assertSame('http://localhost:3000/v1/audience/aud/graphql', (string) $this->sent()->getUri());
    }

    public function testGraphQLErrorsWinOverData(): void
    {
        $this->respondErrors([['message' => 'Refused', 'extensions' => ['code' => 'FORBIDDEN']]], ['rsvpEvent' => null]);
        try {
            $this->signedIn()->graphQL('mutation { rsvpEvent { id } }');
            self::fail('Expected an exception.');
        } catch (AudienceKitException $error) {
            self::assertSame('FORBIDDEN', $error->errorCode);
            self::assertSame('Refused', $error->getMessage());
            self::assertCount(1, $error->errors);
        }
    }

    public function testGraphQLWithoutDataIsADecodingError(): void
    {
        $this->respond(['data' => null]);
        $this->expectException(AudienceKitException::class);
        $this->expectExceptionMessage('no data');
        $this->signedIn()->graphQL('{ id }');
    }

    public function testNonJsonIsADecodingError(): void
    {
        $this->respond('<html>', 200);
        try {
            $this->signedIn()->graphQL('{ id }');
            self::fail('Expected an exception.');
        } catch (AudienceKitException $error) {
            self::assertSame(AudienceKitException::CODE_DECODING, $error->errorCode);
        }
    }

    public function testAJsonScalarIsADecodingError(): void
    {
        $this->respond('"just a string"', 200);
        $this->expectExceptionMessage('not a JSON object');
        $this->signedIn()->graphQL('{ id }');
    }

    public function testNetworkFailure(): void
    {
        $this->http->addException(new TransferException('connection refused'));
        try {
            $this->signedIn()->graphQL('{ id }');
            self::fail('Expected an exception.');
        } catch (AudienceKitException $error) {
            self::assertSame(AudienceKitException::CODE_NETWORK, $error->errorCode);
            self::assertSame('connection refused', $error->getMessage());
        }
    }

    public function testABodyThatIsNotJsonIsRefusedBeforeSending(): void
    {
        $this->expectException(AudienceKitException::class);
        $this->expectExceptionMessage('not JSON');
        $this->signedIn()->request(new ApiRequest('/v1/x', 'POST', body: ['bad' => "\xB1\x31"]));
    }

    // Session ends

    public function testA401EndsTheSession(): void
    {
        $this->respond(['error' => 'unauthenticated'], 401);
        $store = new InMemoryCredentialStore($this->credential());
        $session = $this->session(store: $store);
        self::assertTrue($session->isSignedIn());
        try {
            $session->graphQL('{ id }');
            self::fail('Expected an exception.');
        } catch (AudienceKitException $error) {
            self::assertTrue($error->isUnauthenticated());
        }
        self::assertNull($store->load());
        self::assertFalse($session->isSignedIn());
        self::assertNull($session->credential());
        self::assertNull($session->sessionToken());
    }

    public function testSessionRejectedOnlyForTheStoredToken(): void
    {
        $store = new InMemoryCredentialStore($this->credential('live'));
        $session = $this->session(store: $store);
        self::assertFalse($session->sessionRejected(null));
        self::assertFalse($session->sessionRejected('stale'));
        self::assertNotNull($store->load());
        self::assertTrue($session->sessionRejected('live'));
        self::assertNull($store->load());
        self::assertFalse($session->sessionRejected('live'));
    }

    public function testAuthenticatedRestNeedsASession(): void
    {
        try {
            $this->session()->request(new ApiRequest('/v1/admin/choices', 'POST'));
            self::fail('Expected an exception.');
        } catch (AudienceKitException $error) {
            self::assertSame(AudienceKitException::CODE_NOT_SIGNED_IN, $error->errorCode);
        }
        self::assertCount(0, $this->http->getRequests());
    }

    // REST errors

    /** @return iterable<string, array{int, mixed, string, ?string}> */
    public static function restErrors(): iterable
    {
        yield '403 default' => [403, '', 'FORBIDDEN', "You don't have access to this."];
        yield '403 message' => [403, ['message' => 'Members only'], 'FORBIDDEN', 'Members only'];
        yield '404' => [404, ['message' => 'No such venue'], 'NOT_FOUND', 'No such venue'];
        yield '404 default' => [404, '', 'NOT_FOUND', "That isn't available."];
        yield '409' => [409, '', 'CONFLICT', null];
        yield '422 coded' => [422, ['error' => 'invalid', 'message' => 'Bad'], 'INVALID', 'Bad'];
        yield '429' => [429, '', 'RATE_LIMITED', null];
        yield '500' => [500, '', 'INTERNAL', 'The server responded with status 500.'];
        yield '418' => [418, '', 'HTTP', null];
        yield '400 plain' => [400, ['error' => 'nope'], 'NOPE', null];
        yield '400 fault' => [400, ['fault' => ['message' => 'Faulted']], 'INVALID', 'Faulted'];
        yield '426' => [426, ['minimum_sdk_version' => '9.0.0', 'message' => 'Old'], 'UPDATE_REQUIRED', 'Old'];
        yield '426 bare' => [426, '', 'UPDATE_REQUIRED', null];
        yield 'api version' => [
            400, ['error' => 'unsupported_api_version', 'supported' => ['2027-01-01']],
            'UNSUPPORTED_API_VERSION', 'This version of the app is out of date. Update it to keep going. (API versions served: 2027-01-01.)',
        ];
        yield 'api version message' => [
            400, ['error' => 'unsupported_api_version', 'message' => 'Too old'], 'UNSUPPORTED_API_VERSION', 'Too old',
        ];
    }

    /** @dataProvider restErrors */
    public function testRestErrors(int $status, mixed $body, string $code, ?string $message): void
    {
        $this->respond($body, $status);
        try {
            $this->signedIn()->request(new ApiRequest('/v1/x'));
            self::fail('Expected an exception.');
        } catch (AudienceKitException $error) {
            self::assertSame($code, $error->errorCode);
            self::assertSame($status, $error->status);
            if ($message !== null) {
                self::assertSame($message, $error->getMessage());
            }
            if ($status === 426) {
                self::assertSame(is_array($body) ? '9.0.0' : '', $error->minimumSdkVersion);
            }
        }
    }

    public function testRequestReturnsTheBodyAndSendsQueryParameters(): void
    {
        $this->respond('{"ok":true}');
        $body = $this->signedIn()->request(new ApiRequest('/v1/x', query: ['a' => 'b c', 'd' => 'e']));
        self::assertSame('{"ok":true}', $body);
        self::assertSame('https://api.audiencekit.com/v1/x?a=b%20c&d=e', (string) $this->sent()->getUri());
        self::assertSame('GET', $this->sent()->getMethod());
        self::assertFalse($this->sent()->hasHeader('Content-Type'));
    }

    public function testUrlResolvesRelativePaths(): void
    {
        $session = $this->session(new Configuration(baseUrl: 'https://api.audiencekit.com/'));
        self::assertNull($session->url(null));
        self::assertNull($session->url(''));
        self::assertSame('https://cdn.example/x.png', $session->url('https://cdn.example/x.png'));
        self::assertSame('https://api.audiencekit.com/rails/blobs/x', $session->url('/rails/blobs/x'));
    }

    // Sign-in

    public function testSignInWithFacebookToken(): void
    {
        $this->respond(self::CREDENTIAL_JSON);
        $store = new InMemoryCredentialStore();
        $session = $this->session(new Configuration(host: 'hotmess.social', facebookAppId: '123'), $store);
        $credential = $session->signInWithFacebookToken('fb-token', new DeviceDescription('server-1'));

        self::assertSame('new-token', $credential->token);
        self::assertSame('new-token', $store->load()?->token);
        self::assertTrue($session->isSignedIn());
        self::assertSame('https://api.audiencekit.com/v1/token', (string) $this->sent()->getUri());
        self::assertFalse($this->sent()->hasHeader('Authorization'));
        self::assertSame([
            'facebook_token' => 'fb-token', 'host' => 'hotmess.social', 'facebook_app_id' => '123',
            'device' => ['identifier' => 'server-1', 'type' => 'web'],
        ], $this->sentJson());
    }

    public function testSignInWithFacebookCode(): void
    {
        $this->respond(self::CREDENTIAL_JSON);
        $this->session()->signInWithFacebookCode('code', 'https://app/cb', new DeviceDescription('d'));
        $json = $this->sentJson();
        self::assertSame('code', $json['code']);
        self::assertSame('https://app/cb', $json['redirect_uri']);
        self::assertArrayNotHasKey('host', $json);
        self::assertArrayNotHasKey('connect', $json);
    }

    public function testSignInWithApple(): void
    {
        $this->respond(self::CREDENTIAL_JSON);
        $this->session(new Configuration(host: 'h'))
            ->signInWithAppleIdentityToken('apple', new DeviceDescription('d'), 'Ada', null);
        self::assertSame('https://api.audiencekit.com/v1/token/apple', (string) $this->sent()->getUri());
        self::assertSame(
            ['identity_token' => 'apple', 'first_name' => 'Ada', 'host' => 'h', 'device' => ['identifier' => 'd', 'type' => 'web']],
            $this->sentJson(),
        );
    }

    public function testConnectFacebookIsAuthenticated(): void
    {
        $this->respond(self::CREDENTIAL_JSON);
        $credential = $this->signedIn()->connectFacebook('code', 'https://app/cb', new DeviceDescription('d'));
        self::assertSame('user-2', $credential->userId);
        self::assertSame('Bearer secret-token', $this->sent()->getHeaderLine('Authorization'));
        self::assertTrue($this->sentJson()['connect']);
    }

    public function testConnectFacebookNeedsASession(): void
    {
        $this->expectException(AudienceKitException::class);
        $this->expectExceptionMessage('not signed in');
        $this->session()->connectFacebook('code', 'https://app/cb', new DeviceDescription('d'));
    }

    public function testSignInRejected(): void
    {
        $this->respond(['error' => 'unauthorized'], 401);
        try {
            $this->session()->signInWithFacebookToken('bad', new DeviceDescription('d'));
            self::fail('Expected an exception.');
        } catch (AudienceKitException $error) {
            self::assertSame(AudienceKitException::CODE_SIGN_IN_REJECTED, $error->errorCode);
        }
    }

    public function testSignInFailedCarriesTheApisMessage(): void
    {
        $this->respond(['fault' => ['message' => 'Facebook said no']], 400);
        try {
            $this->session()->signInWithFacebookToken('bad', new DeviceDescription('d'));
            self::fail('Expected an exception.');
        } catch (AudienceKitException $error) {
            self::assertSame(AudienceKitException::CODE_SIGN_IN_FAILED, $error->errorCode);
            self::assertSame('Facebook said no', $error->getMessage());
        }
    }

    public function testSignInOnAnUnsupportedApiVersion(): void
    {
        $this->respond(['error' => 'unsupported_api_version'], 400);
        try {
            $this->session()->signInWithFacebookToken('t', new DeviceDescription('d'));
            self::fail('Expected an exception.');
        } catch (AudienceKitException $error) {
            self::assertSame(AudienceKitException::CODE_UNSUPPORTED_API_VERSION, $error->errorCode);
        }
    }

    public function testSignInOnAServerError(): void
    {
        $this->respond('', 503);
        try {
            $this->session()->signInWithFacebookToken('t', new DeviceDescription('d'));
            self::fail('Expected an exception.');
        } catch (AudienceKitException $error) {
            self::assertSame(AudienceKitException::CODE_INTERNAL, $error->errorCode);
        }
    }

    public function testSignInWithAMalformedCredential(): void
    {
        $this->respond(['token' => 'only']);
        try {
            $this->session()->signInWithFacebookToken('t', new DeviceDescription('d'));
            self::fail('Expected an exception.');
        } catch (AudienceKitException $error) {
            self::assertSame(AudienceKitException::CODE_DECODING, $error->errorCode);
        }
    }

    public function testAdoptAndStorageFailure(): void
    {
        $store = new InMemoryCredentialStore();
        $session = $this->session(store: $store);
        $session->adopt($this->credential('adopted'));
        self::assertSame('adopted', $store->load()?->token);

        $failing = new class () implements CredentialStore {
            public function load(): ?Credential
            {
                throw new RuntimeException('disk');
            }

            public function save(Credential $credential): void
            {
                throw new RuntimeException('read-only');
            }

            public function delete(): void
            {
                throw new RuntimeException('read-only');
            }
        };
        $session = $this->session(store: $failing);
        self::assertFalse($session->isSignedIn());
        self::assertFalse($session->sessionRejected('x'));
        try {
            $session->adopt($this->credential());
            self::fail('Expected an exception.');
        } catch (AudienceKitException $error) {
            self::assertSame(AudienceKitException::CODE_STORAGE, $error->errorCode);
            self::assertStringContainsString('read-only', $error->getMessage());
        }
        // Signing out forgives the store: there is nothing to revoke.
        $session->signOut();
        self::assertCount(0, $this->http->getRequests());
    }

    public function testSwitchAudience(): void
    {
        $this->respond(['token' => 'other', 'userId' => 'u', 'audienceId' => 'aud-2', 'role' => 'admin', 'endpoint' => 'https://api.audiencekit.com/v1/audience/aud-2/graphql']);
        $this->respondData(['id' => 'aud-2']);
        $session = $this->signedIn(new Configuration());
        $credential = $session->switchAudience('aud-2');
        self::assertSame('aud-2', $credential->audienceId);
        self::assertSame(['audience_id' => 'aud-2'], $this->sentJson(0));
        self::assertSame('https://api.audiencekit.com/v1/admin/choices', (string) $this->sent(0)->getUri());
        $session->graphQL('{ id }');
        self::assertSame('https://api.audiencekit.com/v1/audience/aud-2/graphql', (string) $this->sent()->getUri());
        self::assertSame('Bearer other', $this->sent()->getHeaderLine('Authorization'));
    }

    public function testSignOutRevokesTheToken(): void
    {
        $this->respond('', 204);
        $store = new InMemoryCredentialStore($this->credential());
        $session = $this->session(store: $store);
        $session->signOut();
        self::assertNull($store->load());
        self::assertSame('DELETE', $this->sent()->getMethod());
        self::assertSame('https://api.audiencekit.com/v1/token', (string) $this->sent()->getUri());
        self::assertSame('Bearer secret-token', $this->sent()->getHeaderLine('Authorization'));
    }

    public function testSignOutForgivesAGoneSession(): void
    {
        $this->respond('', 401);
        $this->signedIn()->signOut();
        $this->respond('', 404);
        $this->signedIn()->signOut();
        self::assertCount(2, $this->http->getRequests());
    }

    public function testSignOutReportsOtherFailures(): void
    {
        $this->respond('', 500);
        $store = new InMemoryCredentialStore($this->credential());
        try {
            $this->session(store: $store)->signOut();
            self::fail('Expected an exception.');
        } catch (AudienceKitException $error) {
            self::assertSame(500, $error->status);
        }
        self::assertNull($store->load());
    }

    public function testSignOutWithoutASessionSendsNothing(): void
    {
        $this->session()->signOut();
        self::assertCount(0, $this->http->getRequests());
    }

    // Branding and audience

    public function testBranding(): void
    {
        $this->respond(['audience' => ['id' => 'aud-b', 'name' => 'Hot Mess']]);
        $branding = $this->session(new Configuration(host: 'hotmess.social'))->branding(app: 'social.hotmess.app');
        self::assertSame('Hot Mess', $branding['audience']['name']);
        self::assertSame('https://api.audiencekit.com/v1/branding?host=hotmess.social&app=social.hotmess.app', (string) $this->sent()->getUri());
        self::assertFalse($this->sent()->hasHeader('Authorization'));
    }

    public function testBrandingNeedsAHost(): void
    {
        try {
            $this->session(new Configuration())->branding();
            self::fail('Expected an exception.');
        } catch (AudienceKitException $error) {
            self::assertSame(AudienceKitException::CODE_MISSING_CONFIGURATION, $error->errorCode);
        }
    }

    public function testAudienceIdComesFromBrandingAndIsCached(): void
    {
        $this->respond(['audience' => ['id' => 'aud-b']]);
        $this->respondData(['id' => 'aud-b']);
        $session = $this->signedIn(new Configuration(host: 'hotmess.social'), $this->credential(audienceId: null));
        self::assertSame('aud-b', $session->audienceId());
        self::assertSame('aud-b', $session->audienceId());
        $session->graphQL('{ id }');
        self::assertCount(2, $this->http->getRequests());
        self::assertStringEndsWith('/v1/audience/aud-b/graphql', (string) $this->sent()->getUri());
    }

    public function testAudienceIdWithoutAnythingToGoOn(): void
    {
        try {
            $this->session(new Configuration())->audienceId();
            self::fail('Expected an exception.');
        } catch (AudienceKitException $error) {
            self::assertSame(AudienceKitException::CODE_MISSING_CONFIGURATION, $error->errorCode);
        }
        self::assertNull($this->session(new Configuration())->cachedSchemaFields(['Venue']));
    }

    public function testBrandingWithoutAnAudienceId(): void
    {
        $this->respond(['audience' => ['name' => 'x']]);
        $this->expectExceptionMessage('no audience id');
        $this->session(new Configuration(host: 'h'))->audienceId();
    }

    public function testCredentialAudienceWinsOverConfiguration(): void
    {
        $session = $this->signedIn(new Configuration(audienceId: 'configured'), $this->credential(audienceId: 'cred'));
        self::assertSame('cred', $session->audienceId());
        $platform = $this->signedIn(new Configuration(audienceId: 'configured'), $this->credential(audienceId: null));
        self::assertSame('configured', $platform->audienceId());
    }

    // Schema fields

    public function testSchemaFieldsAreAskedOnceAndCached(): void
    {
        $this->respondData([
            't0' => null,
            't1' => ['fields' => [['name' => 'id'], ['name' => 'name'], ['name' => 'chat']]],
        ]);
        $session = $this->signedIn();
        self::assertNull($session->cachedSchemaFields(['Venue']));
        $fields = $session->schemaFields(['Venue', 'Nope', 'Venue']);
        self::assertSame(['Venue' => ['id', 'name', 'chat']], $fields);
        self::assertStringContainsString('t0: __type(name: "Nope")', $this->sentQuery());
        self::assertStringContainsString('t1: __type(name: "Venue")', $this->sentQuery());
        self::assertSame('SchemaFields', $this->sentJson()['operationName']);

        self::assertSame(['Venue' => ['id', 'name', 'chat']], $session->schemaFields(['Nope', 'Venue']));
        self::assertSame(['Venue' => ['id', 'name', 'chat']], $session->cachedSchemaFields(['Venue', 'Nope']));
        self::assertNull($session->cachedSchemaFields(['Venue', 'Other']));
        self::assertCount(1, $this->http->getRequests());
    }

    public function testSignInClearsTheSchemaCache(): void
    {
        $this->respondData(['t0' => ['fields' => [['name' => 'id']]]]);
        $this->respond(self::CREDENTIAL_JSON);
        $session = $this->signedIn();
        $session->schemaFields(['Venue']);
        $session->signInWithFacebookToken('t', new DeviceDescription('d'));
        self::assertNull($session->cachedSchemaFields(['Venue']));
    }
}
