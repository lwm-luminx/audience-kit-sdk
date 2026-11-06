<?php

declare(strict_types=1);

namespace AudienceKit;

/**
 * Which build of the app is calling. Staging builds talk to the production API but sign people in with the
 * audience's staging Facebook app; the client says so with the `X-AudienceKit-Environment: staging` header.
 * Production builds leave the header out. A value the SDK doesn't know (one a newer API defines) is sent as is.
 */
final class Environment
{
    public const PRODUCTION = 'production';
    public const STAGING = 'staging';

    /** The header that carries the environment. */
    public const HEADER = 'X-AudienceKit-Environment';

    /** The environments this SDK knows. */
    public const KNOWN = [self::PRODUCTION, self::STAGING];

    private function __construct()
    {
    }
}
