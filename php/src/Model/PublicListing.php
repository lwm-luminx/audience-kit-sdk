<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/**
 * A venue, event or post as the audience's websites show it (`GET /v1/public/listings`), for a site that lists them
 * with a `public:read` service token.
 */
final class PublicListing extends Model
{
    /** "venue", "event" or "post". */
    public readonly string $kind;
    public readonly string $id;
    /** Its path on the audience's website, e.g. `/venues/<id>`. */
    public readonly ?string $path;
    /** "public" or "community". */
    public readonly ?string $visibility;
    public readonly ?string $title;
    /** Plain text. */
    public readonly ?string $description;
    public readonly ?string $address;
    public readonly ?string $phone;
    public readonly ?string $website;
    /** Whether a venue is listed among venues to go out to. */
    public readonly ?bool $listed;
    public readonly ?string $image;
    public readonly ?\DateTimeImmutable $startAt;
    public readonly ?\DateTimeImmutable $endAt;
    public readonly ?string $venueName;
    public readonly ?string $ticketUrl;
    public readonly ?bool $isCanceled;
    public readonly ?int $coverCents;

    protected function hydrate(array $raw): void
    {
        $this->kind = self::string($raw, 'kind') ?? '';
        $this->id = self::id($raw);
        $this->path = self::string($raw, 'path');
        $this->visibility = self::string($raw, 'visibility');
        $this->title = self::string($raw, 'title');
        $this->description = self::string($raw, 'description');
        $this->address = self::string($raw, 'address');
        $this->phone = self::string($raw, 'phone');
        $this->website = self::string($raw, 'website');
        $this->listed = self::bool($raw, 'listed');
        $this->image = self::string($raw, 'image');
        $this->startAt = self::date($raw, 'start_at');
        $this->endAt = self::date($raw, 'end_at');
        $this->venueName = self::string($raw, 'venue_name');
        $this->ticketUrl = self::string($raw, 'ticket_url');
        $this->isCanceled = self::bool($raw, 'is_canceled');
        $this->coverCents = self::int($raw, 'cover_cents');
    }

    /** Whether the audience shows it in full to anyone, not only to its community. */
    public function isPublic(): bool
    {
        return $this->visibility === null || $this->visibility === 'public';
    }
}
