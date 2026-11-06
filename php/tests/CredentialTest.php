<?php

declare(strict_types=1);

namespace AudienceKit\Tests;

use AudienceKit\AudienceKit;
use AudienceKit\Credential;
use AudienceKit\DeviceDescription;
use AudienceKit\InMemoryCredentialStore;
use DateTimeImmutable;
use InvalidArgumentException;

final class CredentialTest extends TestCase
{
    public function testRoundTripsTheApiShape(): void
    {
        $json = [
            'token' => 't', 'userId' => 'u', 'audienceId' => 'a', 'role' => 'admin',
            'endpoint' => 'https://api.audiencekit.com/v1/audience/a/graphql', 'venueDeviceId' => 'd',
            'expiresAt' => '2030-01-02T03:04:05.000+00:00', 'apiVersion' => '2026-01-01',
        ];
        $credential = Credential::fromArray($json);
        self::assertSame('t', $credential->token);
        self::assertSame('admin', $credential->role);
        self::assertSame('d', $credential->venueDeviceId);
        self::assertSame('2026-01-01', $credential->apiVersion);
        self::assertEquals(new DateTimeImmutable('2030-01-02T03:04:05Z'), $credential->expiresAt);
        self::assertSame($json, $credential->toArray());
        self::assertSame($json, Credential::fromArray($credential->toArray())->toArray());
    }

    public function testDefaultsAndOrigin(): void
    {
        $credential = Credential::fromArray([
            'token' => 't', 'userId' => 'u', 'role' => 'member', 'audienceId' => null,
            'endpoint' => 'http://localhost:3000/v1/audience/a/graphql',
        ]);
        self::assertNull($credential->audienceId);
        self::assertNull($credential->expiresAt);
        self::assertSame(AudienceKit::API_VERSION, $credential->apiVersion);
        self::assertSame('http://localhost:3000', $credential->origin());
        self::assertNull($this->credential(endpoint: 'not a url')->origin());
        self::assertNull($credential->toArray()['expiresAt']);
    }

    public function testExpiry(): void
    {
        self::assertFalse($this->credential()->isExpired());
        $expiring = new Credential('t', 'u', 'a', 'member', self::ENDPOINT, expiresAt: new DateTimeImmutable('2020-01-01'));
        self::assertTrue($expiring->isExpired());
        self::assertFalse($expiring->isExpired(new DateTimeImmutable('2019-12-31')));
    }

    public function testRejectsMissingKeys(): void
    {
        $this->expectException(InvalidArgumentException::class);
        $this->expectExceptionMessage('no role');
        Credential::fromArray(['token' => 't', 'userId' => 'u', 'endpoint' => 'x']);
    }

    public function testRejectsABadExpiry(): void
    {
        $this->expectException(InvalidArgumentException::class);
        Credential::fromArray(['token' => 't', 'userId' => 'u', 'role' => 'r', 'endpoint' => 'x', 'expiresAt' => 'never']);
    }

    public function testRejectsANonStringExpiry(): void
    {
        $this->expectException(InvalidArgumentException::class);
        Credential::fromArray(['token' => 't', 'userId' => 'u', 'role' => 'r', 'endpoint' => 'x', 'expiresAt' => 5]);
    }

    public function testInMemoryStore(): void
    {
        $store = new InMemoryCredentialStore();
        self::assertNull($store->load());
        $store->save($this->credential());
        self::assertSame('secret-token', $store->load()?->token);
        $store->delete();
        self::assertNull($store->load());
    }

    public function testDeviceDescriptionLeavesNullsOut(): void
    {
        self::assertSame(['identifier' => 'i', 'type' => 'web'], (new DeviceDescription('i'))->toArray());
        self::assertSame(
            ['identifier' => 'i', 'type' => 'server', 'version' => '1.0'],
            (new DeviceDescription('i', 'server', version: '1.0'))->toArray(),
        );
    }
}
