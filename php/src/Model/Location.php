<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/** Where a venue is: its point and street address. */
final class Location extends Model
{
    public readonly ?string $id;
    public readonly ?\AudienceKit\Coordinate $coordinate;
    public readonly ?string $address;
    /** Its Google place ID, where the audience has Google Places. */
    public readonly ?string $placeId;

    protected function hydrate(array $raw): void
    {
        $this->id = self::string($raw, "id");
        $this->coordinate = self::point($raw["point"] ?? null);
        $this->address = self::string($raw, "address");
        $place = self::at($raw, "places", "placeId");
        $this->placeId = is_string($place) ? $place : null;
    }
}
