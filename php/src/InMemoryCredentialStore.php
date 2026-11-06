<?php

declare(strict_types=1);

namespace AudienceKit;

/** A credential store that lives as long as the object: the default, for scripts and tests. */
final class InMemoryCredentialStore implements CredentialStore
{
    public function __construct(private ?Credential $credential = null)
    {
    }

    public function load(): ?Credential
    {
        return $this->credential;
    }

    public function save(Credential $credential): void
    {
        $this->credential = $credential;
    }

    public function delete(): void
    {
        $this->credential = null;
    }
}
