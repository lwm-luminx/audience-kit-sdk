<?php

declare(strict_types=1);

namespace AudienceKit;

/**
 * Where an {@see AudienceSession} keeps its credential. Back it with something private to the signed-in person (a
 * server-side session, an encrypted cookie); the token is as good as a password. Throw on failure: the session
 * reports it as {@see AudienceKitException::CODE_STORAGE}.
 */
interface CredentialStore
{
    public function load(): ?Credential;

    public function save(Credential $credential): void;

    public function delete(): void;
}
