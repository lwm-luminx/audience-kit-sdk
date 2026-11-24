<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/** A person the audience lists: a promoter, DJ, drag performer or act. */
final class Person extends Model
{
    public readonly string $id;
    public readonly string $name;
    public readonly ?string $avatarUrl;
    public readonly ?string $bannerUrl;
    public readonly ?int $order;
    /** Whether they are listed in every locale. */
    public readonly bool $global;
    public readonly bool $likeRequired;
    /** @var list<Tag> */
    public readonly array $tags;
    /** The locales they are listed in. @var list<Locale> */
    public readonly array $locales;
    /** Their Facebook Page (Listings and Facebook). */
    public readonly ?Page $facebookPage;
    /** Their home venue (People and Venues). */
    public readonly ?Venue $homeVenue;
    /** What they're part of, each `relationship role via node { … }` (People and Events). @var list<array<string, mixed>> */
    public readonly array $involvements;

    protected function hydrate(array $raw): void
    {
        $this->id = self::id($raw);
        $this->name = self::string($raw, 'name') ?? '';
        $this->avatarUrl = self::string($raw, 'avatarUrl');
        $this->bannerUrl = self::string($raw, 'bannerUrl');
        $this->order = self::int($raw, 'order');
        $this->global = self::bool($raw, 'global') ?? false;
        $this->likeRequired = self::bool($raw, 'likeRequired') ?? false;
        $this->tags = Tag::list($raw['tags'] ?? null);
        $this->locales = Locale::list($raw['locales'] ?? null);
        $this->facebookPage = Page::from(self::at($raw, 'profile', 'facebook', 'page'));
        $this->homeVenue = Venue::from(self::at($raw, 'venues', 'home'));
        $edges = self::at($raw, 'events', 'involvements', 'edges');
        $this->involvements = is_array($edges) ? array_values(array_filter($edges, 'is_array')) : [];
    }
}
