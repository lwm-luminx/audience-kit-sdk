<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/**
 * An event: its own fields, then those of the Venues, RSVP, People and Ticketing modules the audience has. A module
 * the audience doesn't have leaves its properties null or empty.
 */
final class Event extends Model
{
    public readonly string $id;
    public readonly string $name;
    public readonly ?string $description;
    public readonly ?\DateTimeImmutable $startAt;
    public readonly ?\DateTimeImmutable $endAt;
    public readonly bool $isFeatured;
    public readonly bool $isCanceled;
    public readonly ?string $bannerUrl;
    /** Where the event came from, e.g. its Facebook event. */
    public readonly ?string $sourceUrl;
    public readonly ?Locale $locale;
    /** @var list<Tag> */
    public readonly array $tags;
    /** The venue's name as the event gives it, even where the venue isn't listed (Venues). */
    public readonly ?string $venueName;
    /** The listed venue it's at (Venues). */
    public readonly ?Venue $venue;
    /** The signed-in user's answer, "ATTENDING", "MAYBE", "DECLINED" or "UNSURE" (RSVP). */
    public readonly ?string $rsvp;
    /** How many are going (RSVP). */
    public readonly ?int $rsvpCount;
    /** @var list<Profile> */
    public readonly array $hosts;
    /** @var list<Profile> */
    public readonly array $lineup;
    /** Its KJ, DJ or VJ (People). @var list<Profile> */
    public readonly array $jockeys;
    /** What to call them, e.g. "KJ". */
    public readonly ?string $jockeyLabel;
    /** Where tickets are sold (Ticketing). */
    public readonly ?string $ticketUrl;
    /** @var list<AdmissionOffer> */
    public readonly array $offers;
    /** Tonight's cover charge (Ticketing and Cover). */
    public readonly ?CoverCharge $cover;

    protected function hydrate(array $raw): void
    {
        $this->id = self::id($raw);
        $this->name = self::string($raw, 'name') ?? '';
        $this->description = self::string($raw, 'description');
        $this->startAt = self::date($raw, 'startAt');
        $this->endAt = self::date($raw, 'endAt');
        $this->isFeatured = self::bool($raw, 'isFeatured') ?? false;
        $this->isCanceled = self::bool($raw, 'isCanceled') ?? false;
        $this->bannerUrl = self::string($raw, 'bannerUrl');
        $this->sourceUrl = self::string($raw, 'sourceUrl');
        $this->locale = Locale::from($raw['locale'] ?? null);
        $this->tags = Tag::list($raw['tags'] ?? null);
        $venue = is_array($raw['venue'] ?? null) ? $raw['venue'] : [];
        $this->venueName = self::string($venue, 'name');
        $this->venue = Venue::from($venue['venue'] ?? null);
        $this->rsvp = is_string(self::at($raw, 'rsvp', 'mine')) ? self::at($raw, 'rsvp', 'mine') : null;
        $count = self::at($raw, 'rsvp', 'count');
        $this->rsvpCount = is_int($count) ? $count : null;
        $this->hosts = Profile::list(self::at($raw, 'people', 'hosts'));
        $this->lineup = Profile::list(self::at($raw, 'people', 'lineup'));
        $this->jockeys = Profile::list(self::at($raw, 'people', 'jockeys'));
        $label = self::at($raw, 'people', 'jockeyLabel');
        $this->jockeyLabel = is_string($label) ? $label : null;
        $url = self::at($raw, 'tickets', 'url');
        $this->ticketUrl = is_string($url) ? $url : null;
        $this->offers = AdmissionOffer::list(self::at($raw, 'tickets', 'offers'));
        $this->cover = CoverCharge::from(self::at($raw, 'tickets', 'cover', 'charge'));
    }

    /**
     * Who runs the night: its hosts, or, when nobody else is linked to it, its KJ, DJ or VJ (a jockey who is the only
     * person on an event is its host everywhere).
     *
     * @return list<Profile>
     */
    public function effectiveHosts(): array
    {
        return $this->hosts === [] && $this->lineup === [] ? $this->jockeys : $this->hosts;
    }

    /** Whether it has ended at `$at` (now by default); an event with no end has ended once it started. */
    public function hasEnded(?\DateTimeInterface $at = null): bool
    {
        $end = $this->endAt ?? $this->startAt;

        return $end !== null && $end <= ($at ?? new \DateTimeImmutable());
    }
}
