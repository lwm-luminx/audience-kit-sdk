<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/** One page of articles, and the cursor for the next ({@see \AudienceKit\AudienceSession::articlesPage()}). */
final class ArticlesPage
{
    /**
     * @param list<Article> $articles
     * @param string|null   $endCursor Pass as `after` for the next page; null on the last.
     */
    public function __construct(
        public readonly array $articles = [],
        public readonly ?string $endCursor = null,
        public readonly bool $hasNextPage = false,
    ) {
    }

    /** A page from a connection's JSON (`nodes pageInfo { endCursor hasNextPage }`). */
    public static function fromConnection(mixed $connection): self
    {
        if (!is_array($connection)) {
            return new self();
        }
        $cursor = $connection['pageInfo']['endCursor'] ?? null;
        $more = ($connection['pageInfo']['hasNextPage'] ?? false) === true && is_string($cursor);

        return new self(Article::list($connection['nodes'] ?? null), $more ? $cursor : null, $more);
    }
}
