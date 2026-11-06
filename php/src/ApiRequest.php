<?php

declare(strict_types=1);

namespace AudienceKit;

/**
 * An HTTP request to one of the API's REST endpoints, for calls the GraphQL schema doesn't cover (sign-in and
 * branding, for example).
 */
final class ApiRequest
{
    /**
     * @param string                $method
     * @param string                $path          The path under the base URL, e.g. `/v1/branding`.
     * @param array<string, string> $query         Query parameters.
     * @param mixed                 $body          A JSON-encodable body, or null.
     * @param bool                  $authenticated Whether to send the session token. A 401 on an authenticated
     *                                             request ends the session.
     * @param array<string, string> $headers       Headers beyond the ones every call carries.
     */
    public function __construct(
        public readonly string $path,
        public readonly string $method = 'GET',
        public readonly array $query = [],
        public readonly mixed $body = null,
        public readonly bool $authenticated = true,
        public readonly array $headers = [],
    ) {
    }
}
