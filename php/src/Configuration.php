<?php

declare(strict_types=1);

namespace AudienceKit;

/** Where the SDK talks to and which audience it speaks for. */
final class Configuration
{
    /**
     * @param string      $baseUrl                  The API's base URL, e.g. `https://api.audiencekit.com` or
     *                                              `http://localhost:3000`.
     * @param string|null $host                     A host that names the audience, e.g. `hotmess.social` once that
     *                                              domain is verified, or `hotmess.admin.audiencekit.com`. Sent with
     *                                              sign-in so the session is bound to the audience, and used to look
     *                                              up branding.
     * @param string|null $audienceId               The audience's ID (a UUID). When null the session works it out
     *                                              from the stored credential's `audienceId`, or from branding for
     *                                              `$host`.
     * @param string|null $facebookAppId            The Facebook app the build signs people in with.
     * @param string      $environment              {@see Environment::PRODUCTION} or {@see Environment::STAGING}.
     * @param list<string> $trustedCredentialOrigins Other API instances whose sign-ins `$baseUrl` also takes (its
     *                                              TRUSTED_API_ORIGIN): a credential one of them issued is sent to
     *                                              `$baseUrl` rather than its own instance.
     */
    public function __construct(
        public readonly string $baseUrl = AudienceKit::PRODUCTION_BASE_URL,
        public readonly ?string $host = null,
        public readonly ?string $audienceId = null,
        public readonly ?string $facebookAppId = null,
        public readonly string $environment = Environment::PRODUCTION,
        public readonly array $trustedCredentialOrigins = [],
    ) {
    }

    /**
     * The API instance to send `$credential` to: the one that issued it (its endpoint's origin), unless `baseUrl`
     * takes that instance's sign-ins (`trustedCredentialOrigins`); `baseUrl` with no credential.
     */
    public function apiBase(?Credential $credential): string
    {
        $origin = $credential?->origin();
        if ($origin === null) {
            return $this->baseUrl;
        }
        foreach ($this->trustedCredentialOrigins as $trusted) {
            if (self::sameOrigin($trusted, $origin)) {
                return $this->baseUrl;
            }
        }

        return $origin;
    }

    /** Whether two URLs name the same scheme, host and port. */
    public static function sameOrigin(string $lhs, string $rhs): bool
    {
        $a = parse_url($lhs);
        $b = parse_url($rhs);
        if ($a === false || $b === false) {
            return false;
        }
        $port = static fn (array $url): int => $url['port'] ?? (($url['scheme'] ?? '') === 'http' ? 80 : 443);

        return strtolower($a['scheme'] ?? '') === strtolower($b['scheme'] ?? '')
            && strtolower($a['host'] ?? '') === strtolower($b['host'] ?? '')
            && $port($a) === $port($b);
    }
}
