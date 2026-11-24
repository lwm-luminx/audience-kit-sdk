<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/** A Soapbox publication: a local outlet (QSaltLake for Salt Lake) or a person's column. */
final class Publication extends Model
{
    public readonly string $id;
    public readonly string $name;
    public readonly ?string $masthead;
    public readonly ?string $about;
    public readonly ?string $websiteUrl;
    public readonly ?string $photoUrl;
    /** Whether the audience vouches for it: its articles run without review. */
    public readonly bool $trusted;
    /** Whether readers may send it op-eds ({@see \AudienceKit\AudienceSession::submitOpEd()}). */
    public readonly bool $acceptsOpEds;
    public readonly ?string $opEdGuidelines;
    /** The locale it covers, `id name`. */
    public readonly ?Locale $locale;
    /** The person it is, for a person's column. */
    public readonly ?Profile $person;
    /** Whether readers can tip to read it without ads, and the tip and how long it lasts. */
    public readonly bool $adFreeOffered;
    public readonly ?int $adFreeTipCents;
    public readonly ?int $adFreeDays;

    protected function hydrate(array $raw): void
    {
        $this->id = self::id($raw);
        $this->name = self::string($raw, 'name') ?? '';
        $this->masthead = self::string($raw, 'masthead');
        $this->about = self::string($raw, 'about');
        $this->websiteUrl = self::string($raw, 'websiteUrl');
        $this->photoUrl = self::string($raw, 'photoUrl');
        $this->trusted = self::bool($raw, 'trusted') ?? false;
        $this->acceptsOpEds = self::bool($raw, 'acceptsOpEds') ?? false;
        $this->opEdGuidelines = self::string($raw, 'opEdGuidelines');
        $this->locale = Locale::from($raw['locale'] ?? null);
        $this->person = Profile::from($raw['person'] ?? null);
        $this->adFreeOffered = self::bool($raw, 'adFreeOffered') ?? false;
        $this->adFreeTipCents = self::int($raw, 'adFreeTipCents');
        $this->adFreeDays = self::int($raw, 'adFreeDays');
    }
}
