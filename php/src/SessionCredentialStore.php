<?php

declare(strict_types=1);

namespace AudienceKit;

use InvalidArgumentException;
use RuntimeException;

/**
 * Keeps the credential in PHP's own session (`$_SESSION`), under `$key`: the store for a website that signs people
 * in. The session data stays on the server; only the session ID goes to the browser in its cookie, so configure that
 * cookie as `Secure`, `HttpOnly` and `SameSite=Lax`. Call `session_regenerate_id(true)` after signing someone in.
 *
 * Pass `$storage` (an array by reference) to keep it somewhere else shaped like `$_SESSION`, as the tests do.
 */
final class SessionCredentialStore implements CredentialStore
{
    /** @var array<string, mixed>|null */
    private ?array $storage = null;

    /** @param array<string, mixed>|null $storage */
    public function __construct(private readonly string $key = 'audiencekit.credential', ?array &$storage = null)
    {
        if ($storage !== null) {
            $this->storage = &$storage;
        }
    }

    public function load(): ?Credential
    {
        $data = $this->storage()[$this->key] ?? null;
        if (!is_array($data)) {
            return null;
        }
        try {
            return Credential::fromArray($data);
        } catch (InvalidArgumentException) {
            return null;
        }
    }

    public function save(Credential $credential): void
    {
        $storage = &$this->storage();
        $storage[$this->key] = $credential->toArray();
    }

    public function delete(): void
    {
        $storage = &$this->storage();
        unset($storage[$this->key]);
    }

    /** @return array<string, mixed> */
    private function &storage(): array
    {
        if ($this->storage !== null) {
            return $this->storage;
        }
        if (session_status() !== PHP_SESSION_ACTIVE) {
            throw new RuntimeException('Start the PHP session (session_start()) before signing in.');
        }

        return $_SESSION;
    }
}
