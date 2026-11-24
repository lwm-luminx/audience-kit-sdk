<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/** Someone as others see them: a name and an avatar. */
final class Profile extends Model
{
    public readonly string $id;
    public readonly string $name;
    public readonly ?string $avatarUrl;

    protected function hydrate(array $raw): void
    {
        $this->id = self::id($raw);
        $this->name = self::string($raw, "name") ?? "";
        $this->avatarUrl = self::string($raw, "avatarUrl");
    }
}
