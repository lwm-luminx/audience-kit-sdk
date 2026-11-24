<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/** The audience: its name, subdomain and theme. */
final class Audience extends Model
{
    public readonly string $id;
    public readonly string $name;
    public readonly ?string $subdomain;
    /** Its theme: `preset`, `tagline`, and `light` and `dark` token lists; {@see color()} reads one. @var array<string, mixed>|null */
    public readonly ?array $theme;

    protected function hydrate(array $raw): void
    {
        $this->id = self::id($raw);
        $this->name = self::string($raw, "name") ?? "";
        $this->subdomain = self::string($raw, "subdomain");
        $this->theme = is_array($raw["theme"] ?? null) ? $raw["theme"] : null;
    }

    /** A theme token's color, preferring its dark override in dark mode. */
    public function color(string $token, bool $dark = false): ?\AudienceKit\Color
    {
        return \AudienceKit\Color::fromTheme($this->theme, $token, $dark);
    }
}
