<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/** A locale: a city or region the audience is organized by. */
final class Locale extends Model
{
    public readonly string $id;
    public readonly string $name;
    /** A short label, e.g. "SLC". */
    public readonly ?string $label;
    /** The cities it covers. @var list<string> */
    public readonly array $cityNames;
    public readonly ?string $bannerUrl;
    /** Its Google place ID, where the audience has Listings and Google Places. */
    public readonly ?string $placeId;

    protected function hydrate(array $raw): void
    {
        $this->id = self::id($raw);
        $this->name = self::string($raw, "name") ?? "";
        $this->label = self::string($raw, "label");
        $this->cityNames = self::strings($raw, "cityNames");
        $this->bannerUrl = self::string($raw, "bannerUrl");
        $place = self::at($raw, "profile", "places", "placeId");
        $this->placeId = is_string($place) ? $place : null;
    }
}
