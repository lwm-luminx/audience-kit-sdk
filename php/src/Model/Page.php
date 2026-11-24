<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/** A Facebook Page a venue or person is linked to (Listings and Facebook). */
final class Page extends Model
{
    public readonly string $id;
    public readonly string $name;
    public readonly ?string $photoUrl;
    public readonly ?string $bannerUrl;

    protected function hydrate(array $raw): void
    {
        $this->id = self::id($raw);
        $this->name = self::string($raw, "name") ?? "";
        $this->photoUrl = self::string($raw, "photoUrl");
        $this->bannerUrl = self::string($raw, "bannerUrl");
    }
}
