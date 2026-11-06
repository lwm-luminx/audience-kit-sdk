<?php

declare(strict_types=1);

namespace AudienceKit;

/**
 * Which fields an audience's schema has, as far as the SDK's documents need to know. The API leaves a module's
 * fields out of an audience that hasn't installed it (Facebook Pages, Google Places, RSVP, Ticketing, Friends…), and
 * asking for one fails the whole operation with `undefinedField`; the SDK builds its documents from this.
 */
final class SchemaShape
{
    /**
     * @param array<string, list<string>>|null $fields Every type's fields, by type; null assumes every field is
     *                                                 there (before the SDK has had to ask).
     */
    public function __construct(public readonly ?array $fields = null)
    {
    }

    /** Assumes every field is there: the first try of each operation, so an audience with every module needs one call. */
    public static function everything(): self
    {
        return new self(null);
    }

    public function has(string $type, string $field): bool
    {
        if ($this->fields === null) {
            return true;
        }

        return in_array($field, $this->fields[$type] ?? [], true);
    }
}
