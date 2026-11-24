<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/** One page of public listings: up to 500 venues, then events, then posts. */
final class PublicListingsPage
{
    /** @param list<PublicListing> $listings */
    public function __construct(
        public readonly array $listings = [],
        public readonly int $pageCount = 1,
        public readonly ?int $nextPage = null,
    ) {
    }

    /** @param array<string, mixed> $json */
    public static function fromArray(array $json): self
    {
        $int = static fn (mixed $value): ?int => is_int($value) ? $value : (is_numeric($value) ? (int) $value : null);

        return new self(
            PublicListing::list($json['listings'] ?? null),
            $int($json['page_count'] ?? null) ?? 1,
            $int($json['next_page'] ?? null),
        );
    }
}
