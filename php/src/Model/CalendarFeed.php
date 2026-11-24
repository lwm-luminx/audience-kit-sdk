<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/**
 * The signed-in person's calendar subscription in the audience: an iCalendar feed Apple Calendar, Google Calendar
 * and Outlook poll, with the events they're going to, their talent's slots, their shifts and every event at the
 * venues they follow.
 */
final class CalendarFeed extends Model
{
    /** The https feed, to copy or share. */
    public readonly string $url;
    /** The same link as webcal://, which Apple Calendar and Outlook open as a subscription. */
    public readonly string $webcalUrl;
    /** Google Calendar's page that adds the subscription. */
    public readonly string $googleUrl;
    /** The venues it follows. @var list<string> */
    public readonly array $venueIds;

    protected function hydrate(array $raw): void
    {
        $this->url = self::string($raw, 'url') ?? '';
        $this->webcalUrl = self::string($raw, 'webcalUrl') ?? (preg_replace('#^https?://#', 'webcal://', $this->url) ?? '');
        $this->googleUrl = self::string($raw, 'googleUrl')
            ?? 'https://calendar.google.com/calendar/render?cid=' . rawurlencode($this->webcalUrl);
        $ids = [];
        foreach (is_array($raw['venues'] ?? null) ? $raw['venues'] : [] as $venue) {
            if (is_array($venue) && is_string($venue['id'] ?? null)) {
                $ids[] = $venue['id'];
            }
        }
        $this->venueIds = $ids;
    }

    /** Whether every event at the venue is in it. */
    public function follows(string $venueId): bool
    {
        return in_array($venueId, $this->venueIds, true);
    }
}
