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
     * @param string                 $userId        The signed-in user's ID.
     * @param string|null            $audienceId    The audience the session is bound to; null for a platform-console
     *                                              session.
     * @param string                 $role          `member`, `listing`, `admin` or `venue_device` today.
     * @param string                 $endpoint      The GraphQL endpoint the token was issued for, as a full URL.
     * @param string|null            $venueDeviceId The venue device this session runs on, for venue-device sessions.
     * @param DateTimeImmutable|null $expiresAt     When the session expires; null when it only ends by signing out.
     * @param string                 $apiVersion    The API version the credential was issued under.
     */
    public function __construct(
        public readonly string $token,
        public readonly string $userId,
        public readonly ?string $audienceId,
        public readonly string $role,
        public readonly string $endpoint,
        public readonly ?string $venueDeviceId = null,
        public readonly ?DateTimeImmutable $expiresAt = null,
        public readonly string $apiVersion = AudienceKit::API_VERSION,
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
        foreach (['token', 'userId', 'role', 'endpoint'] as $key) {
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
            userId: $data['userId'],
            audienceId: isset($data['audienceId']) && is_string($data['audienceId']) ? $data['audienceId'] : null,
            role: $data['role'],
            endpoint: $data['endpoint'],
            venueDeviceId: isset($data['venueDeviceId']) && is_string($data['venueDeviceId'])
                ? $data['venueDeviceId'] : null,
            expiresAt: $expiresAt,
            apiVersion: isset($data['apiVersion']) && is_string($data['apiVersion'])
                ? $data['apiVersion'] : AudienceKit::API_VERSION,
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
        ];
    }

    /** Whether the session has expired at `$at` (now by default). Sessions with no expiry never do. */
    public function isExpired(?DateTimeInterface $at = null): bool
    {
        if ($this->expiresAt === null) {
            return false;
        }

        return $this->expiresAt <= ($at ?? new DateTimeImmutable());
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
