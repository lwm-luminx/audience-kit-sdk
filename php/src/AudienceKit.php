<?php

declare(strict_types=1);

namespace AudienceKit;

/**
 * The SDK's constants: its version, the API contract it speaks and where the hosted API is.
 *
 * Create an {@see AudienceSession} with a {@see Configuration}, sign in (or {@see AudienceSession::adopt()} a
 * credential minted elsewhere), then query the audience's data over GraphQL.
 */
final class AudienceKit
{
    /** The PHP SDK's semantic version. It is versioned on its own, apart from the Swift and Kotlin SDKs' VERSION. */
    public const VERSION = '0.1.1';

    /**
     * The API contract this SDK speaks, the date it was last broken: sent as X-AudienceKit-API-Version on every
     * request and kept on each {@see Credential}.
     */
    public const API_VERSION = '2026-10-11';

    /** The request header that carries {@see API_VERSION}. */
    public const API_VERSION_HEADER = 'X-AudienceKit-API-Version';

    /** The request header that says which SDK is calling. */
    public const CLIENT_HEADER = 'X-AudienceKit-Client';

    /** The hosted AudienceKit API. */
    public const PRODUCTION_BASE_URL = 'https://api.audiencekit.com';

    /** What {@see CLIENT_HEADER} carries: the SDK's name and version. */
    public static function clientHeader(): string
    {
        return 'AudienceKit-PHP/' . self::VERSION;
    }

    /** Whether `$version` (this SDK's by default) is older than `$minimum`, a dotted version like "0.3.0". */
    public static function isOlder(string $minimum, string $version = self::VERSION): bool
    {
        $parts = static fn (string $value): array => array_map('intval', explode('.', $value));
        $mine = $parts($version);
        $theirs = $parts($minimum);
        $count = max(count($mine), count($theirs));
        for ($index = 0; $index < $count; $index++) {
            $a = $mine[$index] ?? 0;
            $b = $theirs[$index] ?? 0;
            if ($a !== $b) {
                return $a < $b;
            }
        }

        return false;
    }
}
