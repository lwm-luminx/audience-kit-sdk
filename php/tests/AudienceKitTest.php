<?php

declare(strict_types=1);

namespace AudienceKit\Tests;

use AudienceKit\AudienceKit;
use AudienceKit\Configuration;
use AudienceKit\Environment;
use AudienceKit\GraphQLEndpoint;

final class AudienceKitTest extends TestCase
{
    public function testVersionIsSemantic(): void
    {
        self::assertMatchesRegularExpression('/^\d+\.\d+\.\d+$/', AudienceKit::VERSION);
        self::assertMatchesRegularExpression('/^\d{4}-\d{2}-\d{2}$/', AudienceKit::API_VERSION);
        self::assertSame('AudienceKit-PHP/' . AudienceKit::VERSION, AudienceKit::clientHeader());
    }

    public function testChangelogHasTheVersion(): void
    {
        $changelog = file_get_contents(__DIR__ . '/../CHANGELOG.md');
        self::assertStringContainsString('## ' . AudienceKit::VERSION . ' ', (string) $changelog);
    }

    public function testIsOlder(): void
    {
        self::assertTrue(AudienceKit::isOlder('0.3.0', '0.2.9'));
        self::assertTrue(AudienceKit::isOlder('1.0', '0.99.99'));
        self::assertFalse(AudienceKit::isOlder('0.3.0', '0.3.0'));
        self::assertFalse(AudienceKit::isOlder('0.3', '0.3.1'));
        self::assertFalse(AudienceKit::isOlder('0.0.1', '1'));
        self::assertFalse(AudienceKit::isOlder('0.0.0'));
    }

    public function testEndpointPath(): void
    {
        self::assertSame('/v1/audience/abc/graphql', GraphQLEndpoint::path('abc'));
        self::assertSame('/v1/audience/a%20b/staff', GraphQLEndpoint::path('a b', 'staff'));
    }

    public function testEnvironmentsKnown(): void
    {
        self::assertSame(['production', 'staging'], Environment::KNOWN);
        self::assertSame('X-AudienceKit-Environment', Environment::HEADER);
    }

    public function testApiBaseFollowsTheCredential(): void
    {
        $configuration = new Configuration(baseUrl: 'https://next.audiencekit.com');
        self::assertSame('https://next.audiencekit.com', $configuration->apiBase(null));
        self::assertSame('https://api.audiencekit.com', $configuration->apiBase($this->credential()));

        $trusting = new Configuration(
            baseUrl: 'https://next.audiencekit.com',
            trustedCredentialOrigins: ['https://api.audiencekit.com:443'],
        );
        self::assertSame('https://next.audiencekit.com', $trusting->apiBase($this->credential()));
        self::assertSame('http://localhost:3000', $trusting->apiBase(
            $this->credential(endpoint: 'http://localhost:3000/v1/audience/x/graphql'),
        ));
    }

    public function testSameOrigin(): void
    {
        self::assertTrue(Configuration::sameOrigin('HTTPS://API.audiencekit.com', 'https://api.audiencekit.com:443/x'));
        self::assertTrue(Configuration::sameOrigin('http://localhost', 'http://localhost:80'));
        self::assertFalse(Configuration::sameOrigin('http://localhost:3000', 'http://localhost:3001'));
        self::assertFalse(Configuration::sameOrigin('https://a.example', 'http://a.example'));
        self::assertFalse(Configuration::sameOrigin('http:///', 'https://a.example'));
    }
}
