<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/** An event's RSVPs: how many are going, the signed-in user's own answer and, where asked for, who's going. */
final class EventRSVP extends Model
{
    /** How many are going. */
    public readonly int $count;
    /** The signed-in user's answer, "ATTENDING", "MAYBE", "DECLINED" or "UNSURE"; null when they haven't answered. */
    public readonly ?string $mine;
    /** Why they count as going: "RSVP", or "TICKET" when they hold one. */
    public readonly ?string $mineSource;
    /** Going, interested and ticket counts (staff only; null otherwise). */
    public readonly ?int $going;
    public readonly ?int $interested;
    public readonly ?int $tickets;
    /** The first attendees, each `profile friend source`. @var list<array<string, mixed>> */
    public readonly array $attendees;

    protected function hydrate(array $raw): void
    {
        $this->count = self::int($raw, 'count') ?? 0;
        $this->mine = self::string($raw, 'mine');
        $this->mineSource = self::string($raw, 'mineSource');
        $counts = is_array($raw['counts'] ?? null) ? $raw['counts'] : [];
        $this->going = self::int($counts, 'going');
        $this->interested = self::int($counts, 'interested');
        $this->tickets = self::int($counts, 'tickets');
        $nodes = self::at($raw, 'attendees', 'nodes');
        $this->attendees = is_array($nodes) ? array_values(array_filter($nodes, 'is_array')) : [];
    }

    /** Whether the signed-in user is going. */
    public function isGoing(): bool
    {
        return $this->mine === 'ATTENDING';
    }

    /** The attendees' profiles. @return list<Profile> */
    public function attendeeProfiles(): array
    {
        return Profile::list(array_map(static fn (array $attendee) => $attendee['profile'] ?? null, $this->attendees));
    }
}
