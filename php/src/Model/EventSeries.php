<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/** A recurring event series, e.g. "Karaoke every Tuesday". */
final class EventSeries extends Model
{
    public readonly string $id;
    public readonly string $name;
    public readonly ?string $description;
    /** How it repeats, for people, e.g. "Every Tuesday". */
    public readonly ?string $recurrenceText;
    /** The first night, `YYYY-MM-DD`. */
    public readonly ?string $startsOn;
    /** When it starts, `HH:MM`, in {@see $timeZone}. */
    public readonly ?string $startTime;
    public readonly ?string $timeZone;
    public readonly ?int $durationMinutes;
    public readonly ?string $bannerUrl;
    public readonly ?Locale $locale;
    /** @var list<Tag> */
    public readonly array $tags;
    public readonly ?string $venueName;
    public readonly ?Venue $venue;

    protected function hydrate(array $raw): void
    {
        $this->id = self::id($raw);
        $this->name = self::string($raw, 'name') ?? '';
        $this->description = self::string($raw, 'description');
        $this->recurrenceText = self::string($raw, 'recurrenceText');
        $this->startsOn = self::string($raw, 'startsOn');
        $this->startTime = self::string($raw, 'startTime');
        $this->timeZone = self::string($raw, 'timeZone');
        $this->durationMinutes = self::int($raw, 'durationMinutes');
        $this->bannerUrl = self::string($raw, 'bannerUrl');
        $this->locale = Locale::from($raw['locale'] ?? null);
        $this->tags = Tag::list($raw['tags'] ?? null);
        $venue = is_array($raw['venue'] ?? null) ? $raw['venue'] : [];
        $this->venueName = self::string($venue, 'name');
        $this->venue = Venue::from($venue['venue'] ?? null);
    }
}
