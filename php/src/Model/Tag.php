<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/** A tag on a venue, person or event, or a tribe people identify with: its name and chip color. */
final class Tag extends Model
{
    public readonly string $id;
    public readonly string $name;
    /** The chip color as hex, e.g. "#ff3366"; {@see color()} parses it. */
    public readonly ?string $colorHex;
    /** Whether it is a tribe people can identify with. */
    public readonly bool $tribe;

    protected function hydrate(array $raw): void
    {
        $this->id = self::id($raw);
        $this->name = self::string($raw, "name") ?? "";
        $this->colorHex = self::string($raw, "color");
        $this->tribe = self::bool($raw, "tribe") ?? false;
    }

    public function color(): ?\AudienceKit\Color
    {
        return $this->colorHex === null ? null : \AudienceKit\Color::fromHex($this->colorHex);
    }
}
