<?php

declare(strict_types=1);

namespace AudienceKit\Model;

/**
 * Everything an audience lists, read in one go ({@see \AudienceKit\AudienceSession::community()}): for a site
 * that builds its pages from it, or an agent that reads it in. A part the audience doesn't have is empty.
 */
final class Community
{
    /**
     * @param list<Locale>      $locales
     * @param list<Venue>       $venues
     * @param list<Person>      $people
     * @param list<Event>       $events
     * @param list<EventSeries> $eventSeries
     */
    public function __construct(
        public readonly ?Audience $audience,
        public readonly array $locales = [],
        public readonly array $venues = [],
        public readonly array $people = [],
        public readonly array $events = [],
        public readonly array $eventSeries = [],
    ) {
    }
}
