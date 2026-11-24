<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/** One of the signed-in user's tribes, and whether they keep it to themselves. */
final class TribeIdentification extends Model
{
    public readonly bool $isPrivate;
    public readonly ?Tag $tag;

    protected function hydrate(array $raw): void
    {
        $this->isPrivate = self::bool($raw, "isPrivate") ?? true;
        $this->tag = Tag::from($raw["tag"] ?? null);
    }
}
