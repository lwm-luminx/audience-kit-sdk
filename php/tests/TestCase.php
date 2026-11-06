<?php

declare(strict_types=1);

namespace AudienceKit\Tests;

use AudienceKit\AudienceSession;
use AudienceKit\Configuration;
use AudienceKit\Credential;
use AudienceKit\CredentialStore;
use AudienceKit\InMemoryCredentialStore;
use Http\Mock\Client as MockClient;
use Nyholm\Psr7\Factory\Psr17Factory;
use Nyholm\Psr7\Response;
use PHPUnit\Framework\TestCase as BaseTestCase;
use Psr\Http\Message\RequestInterface;

abstract class TestCase extends BaseTestCase
{
    public const AUDIENCE_ID = '11111111-2222-3333-4444-555555555555';
    public const ENDPOINT = 'https://api.audiencekit.com/v1/audience/' . self::AUDIENCE_ID . '/graphql';

    protected MockClient $http;

    protected function setUp(): void
    {
        $this->http = new MockClient();
    }

    protected function session(
        ?Configuration $configuration = null,
        ?CredentialStore $store = null,
    ): AudienceSession {
        $factory = new Psr17Factory();

        return new AudienceSession(
            $configuration ?? new Configuration(audienceId: self::AUDIENCE_ID),
            $store ?? new InMemoryCredentialStore(),
            $this->http,
            $factory,
            $factory,
        );
    }

    /** A session signed in with a stored credential. */
    protected function signedIn(?Configuration $configuration = null, ?Credential $credential = null): AudienceSession
    {
        return $this->session($configuration, new InMemoryCredentialStore($credential ?? $this->credential()));
    }

    protected function credential(
        string $token = 'secret-token',
        ?string $audienceId = self::AUDIENCE_ID,
        string $endpoint = self::ENDPOINT,
    ): Credential {
        return new Credential($token, 'user-1', $audienceId, 'member', $endpoint);
    }

    /** Queues a JSON response. @param mixed $body */
    protected function respond(mixed $body, int $status = 200): void
    {
        $this->http->addResponse(new Response(
            $status,
            ['Content-Type' => 'application/json'],
            is_string($body) ? $body : json_encode($body, JSON_THROW_ON_ERROR),
        ));
    }

    /** Queues a GraphQL `data` response. @param array<string, mixed> $data */
    protected function respondData(array $data): void
    {
        $this->respond(['data' => $data]);
    }

    /** Queues a GraphQL `errors` response. @param list<array<string, mixed>> $errors */
    protected function respondErrors(array $errors, mixed $data = null): void
    {
        $this->respond(['errors' => $errors, 'data' => $data]);
    }

    /** The last request sent, or the `$index`th. */
    protected function sent(int $index = -1): RequestInterface
    {
        $requests = $this->http->getRequests();
        self::assertNotEmpty($requests, 'No request was sent.');

        return $requests[$index < 0 ? count($requests) + $index : $index];
    }

    /** @return array<string, mixed> */
    protected function sentJson(int $index = -1): array
    {
        $request = $this->sent($index);
        $request->getBody()->rewind();

        return json_decode((string) $request->getBody(), true, 512, JSON_THROW_ON_ERROR);
    }

    protected function sentQuery(int $index = -1): string
    {
        return $this->sentJson($index)['query'];
    }
}
