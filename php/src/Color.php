<?php

declare(strict_types=1);

namespace AudienceKit;

/**
 * A color from the API's hex strings (a theme token, a tag's chip color), with components from 0 to 1, for pages
 * that draw with the audience's branding.
 */
final class Color
{
    public function __construct(
        public readonly float $red,
        public readonly float $green,
        public readonly float $blue,
        public readonly float $alpha = 1.0,
    ) {
    }

    /** Parses `#rgb`, `#rrggbb` or `#rrggbbaa` (the `#` is optional); null when it is none of those. */
    public static function fromHex(string $hex): ?self
    {
        $digits = ltrim(trim($hex), '#');
        if (strlen($digits) === 3) {
            $digits = implode('', array_map(static fn (string $digit) => $digit . $digit, str_split($digits)));
        }
        if ((strlen($digits) !== 6 && strlen($digits) !== 8) || !ctype_xdigit($digits)) {
            return null;
        }
        if (strlen($digits) === 6) {
            $digits .= 'ff';
        }
        [$red, $green, $blue, $alpha] = array_map(
            static fn (string $pair) => hexdec($pair) / 255,
            str_split($digits, 2),
        );

        return new self($red, $green, $blue, $alpha);
    }

    /**
     * A branding theme token's color, preferring its dark override in dark mode. `$theme` is branding's or the
     * audience's `theme`: `light` and `dark` either as `{ token: hex }` maps (REST branding) or as lists of
     * `{ name, value }` (GraphQL).
     *
     * @param array<string, mixed>|null $theme
     */
    public static function fromTheme(?array $theme, string $token, bool $dark = false): ?self
    {
        $value = static function (mixed $tokens) use ($token): ?string {
            if (!is_array($tokens)) {
                return null;
            }
            if (isset($tokens[$token]) && is_string($tokens[$token])) {
                return $tokens[$token];
            }
            foreach ($tokens as $entry) {
                if (is_array($entry) && ($entry['name'] ?? null) === $token && is_string($entry['value'] ?? null)) {
                    return $entry['value'];
                }
            }

            return null;
        };
        $hex = ($dark ? $value($theme['dark'] ?? null) : null) ?? $value($theme['light'] ?? null);

        return $hex === null ? null : self::fromHex($hex);
    }

    /** The color as CSS `rgba(r, g, b, a)`. */
    public function toCss(): string
    {
        $channel = static fn (float $value) => (int) round(max(0.0, min(1.0, $value)) * 255);
        $alpha = rtrim(rtrim(sprintf('%.3F', max(0.0, min(1.0, $this->alpha))), '0'), '.');

        return sprintf('rgba(%d, %d, %d, %s)', $channel($this->red), $channel($this->green), $channel($this->blue), $alpha);
    }

    /** The color as `#rrggbb`, or `#rrggbbaa` when it isn't opaque. */
    public function toHex(): string
    {
        $channel = static fn (float $value) => sprintf('%02x', (int) round(max(0.0, min(1.0, $value)) * 255));
        $hex = '#' . $channel($this->red) . $channel($this->green) . $channel($this->blue);

        return $this->alpha >= 1.0 ? $hex : $hex . $channel($this->alpha);
    }
}
