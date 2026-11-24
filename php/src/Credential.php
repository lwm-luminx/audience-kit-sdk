<?php

declare(strict_types=1);

namespace AudienceKit;

use DateTimeImmutable;
use DateTimeInterface;
use InvalidArgumentException;

/**
 * A session the API issued, as `POST /v1/token` (every variant) returns it:
 *
 *     { "token": "...", "userId": "...", "audienceId": "...", "role": "member",
 *       "endpoint": "https://api.audiencekit.com/v1/audience/<id>/graphql", "venueDeviceId": null, "expiresAt": null }
 *
 * The credential says everything the client needs about the session, so nothing decodes the JWT. Treat the token
 * like a password: keep it in a {@see CredentialStore} backed by something private and never log it.
 */
final class Credential
{
    /**
     * @param string                 $token         The session JWT, sent as `Authorization: Bearer <token>`.
     * @param string|null            $userId        The signed-in user's ID; null for a service token's session.
     * @param string|null            $audienceId    The audience the session is bound to; null for a platform-console
     *                                              session.
     * @param string                 $role          `member`, `listing`, `admin`, `venue_device` or `service` today.
     * @param string                 $endpoint      The GraphQL endpoint the token was issued for, as a full URL.
     * @param string|null            $venueDeviceId The venue device this session runs on, for venue-device sessions.
     * @param DateTimeImmutable|null $expiresAt     When the session expires; null when it only ends by signing out.
     * @param string                 $apiVersion    The API version the credential was issued under.
     * @param list<string>           $scopes        A service token's scopes, e.g. `public:read`.
     * @param string|null            $audience      A service token's audience name.
     */
    public function __construct(
        public readonly string $token,
        public readonly ?string $userId,
        public readonly ?string $audienceId,
        public readonly string $role,
        public readonly string $endpoint,
        public readonly ?string $venueDeviceId = null,
        public readonly ?DateTimeImmutable $expiresAt = null,
        public readonly string $apiVersion = AudienceKit::API_VERSION,
        public readonly array $scopes = [],
        public readonly ?string $audience = null,
    ) {
    }

    /**
     * A credential from the API's JSON (decoded to an array).
     *
     * @param array<string, mixed> $data
     * @throws InvalidArgumentException when a required key is missing or malformed.
     */
    public static function fromArray(array $data): self
    {
        foreach (['token', 'endpoint'] as $key) {
            if (!isset($data[$key]) || !is_string($data[$key])) {
                throw new InvalidArgumentException("The credential has no $key.");
            }
        }
        $expiresAt = null;
        if (isset($data['expiresAt'])) {
            if (!is_string($data['expiresAt'])) {
                throw new InvalidArgumentException('expiresAt is not a string.');
            }
            if (strtotime($data['expiresAt']) === false) {
                throw new InvalidArgumentException("{$data['expiresAt']} isn't an ISO 8601 date.");
            }
            $expiresAt = new DateTimeImmutable($data['expiresAt']);
        }

        return new self(
            token: $data['token'],
            userId: isset($data['userId']) && is_string($data['userId']) ? $data['userId'] : null,
            audienceId: isset($data['audienceId']) && is_string($data['audienceId']) ? $data['audienceId'] : null,
            role: isset($data['role']) && is_string($data['role']) ? $data['role'] : 'member',
            endpoint: $data['endpoint'],
            venueDeviceId: isset($data['venueDeviceId']) && is_string($data['venueDeviceId'])
                ? $data['venueDeviceId'] : null,
            expiresAt: $expiresAt,
            apiVersion: isset($data['apiVersion']) && is_string($data['apiVersion'])
                ? $data['apiVersion'] : AudienceKit::API_VERSION,
            scopes: isset($data['scopes']) && is_array($data['scopes'])
                ? array_values(array_filter($data['scopes'], 'is_string')) : [],
            audience: isset($data['audience']) && is_string($data['audience']) ? $data['audience'] : null,
        );
    }

    /** The credential as the API's JSON shape, for storing. @return array<string, mixed> */
    public function toArray(): array
    {
        return [
            'token' => $this->token,
            'userId' => $this->userId,
            'audienceId' => $this->audienceId,
            'role' => $this->role,
            'endpoint' => $this->endpoint,
            'venueDeviceId' => $this->venueDeviceId,
            'expiresAt' => $this->expiresAt?->format(DateTimeInterface::RFC3339_EXTENDED),
            'apiVersion' => $this->apiVersion,
        ] + array_filter(['scopes' => $this->scopes, 'audience' => $this->audience], static fn ($value) => $value !== [] && $value !== null);
    }

    /** Whether the session has expired at `$at` (now by default). Sessions with no expiry never do. */
    public function isExpired(?DateTimeInterface $at = null): bool
    {
        if ($this->expiresAt === null) {
            return false;
        }

        return $this->expiresAt <= ($at ?? new DateTimeImmutable());
    }

    /** Whether the session expires within `$seconds` of `$at` (now by default). */
    public function expiresWithin(int $seconds, ?DateTimeInterface $at = null): bool
    {
        if ($this->expiresAt === null) {
            return false;
        }
        $now = DateTimeImmutable::createFromInterface($at ?? new DateTimeImmutable());

        return $this->expiresAt <= $now->modify("+$seconds seconds");
    }

    /** Whether this is a service token's session (no person behind it). */
    public function isService(): bool
    {
        return $this->role === 'service';
    }

    /** Whether a service token's session may do what `$scope` covers, e.g. `public:read`. */
    public function hasScope(string $scope): bool
    {
        return in_array($scope, $this->scopes, true);
    }

    /** Keeps the token out of var_dump() and print_r() output. @return array<string, mixed> */
    public function __debugInfo(): array
    {
        return ['token' => '<redacted>'] + $this->toArray();
    }

    /** The API instance the endpoint is on: its scheme, host and port, and nothing else. */
    public function origin(): ?string
    {
        $url = parse_url($this->endpoint);
        if ($url === false || !isset($url['scheme'], $url['host'])) {
            return null;
        }

        return $url['scheme'] . '://' . $url['host'] . (isset($url['port']) ? ':' . $url['port'] : '');
    }
}
