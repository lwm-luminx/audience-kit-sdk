<?php

declare(strict_types=1);

namespace AudienceKit;

/**
 * The calls every AudienceKit app makes, so apps are built with little custom code: the same operations the Swift
 * and Kotlin SDKs run, returning the API's JSON as arrays (keys as the schema names them; dates as ISO 8601
 * strings). Fields a module adds are missing where the audience hasn't installed that module: the SDK asks for them
 * and, if the audience's schema doesn't have one, asks again without.
 */
trait Operations
{
    /** The audience: its name, subdomain and theme. @return array<string, mixed> */
    public function audience(): array
    {
        return $this->graphQL(Queries::AUDIENCE, null, 'Audience');
    }

    /** The signed-in user's own profile (`me { self }`), or null when the API has none. @return array<string, mixed>|null */
    public function me(): ?array
    {
        $profile = $this->graphQL(Queries::ME, null, 'Me')['me']['self'] ?? null;

        return is_array($profile) ? $profile : null;
    }

    /** The audience's venues. @return list<array<string, mixed>> */
    public function venues(): array
    {
        $data = $this->shapedGraphQL(Queries::LISTING_TYPES, Queries::venues(...), null, 'Venues');

        return self::nodes($data['venues']['list'] ?? null);
    }

    /** The audience's people: promoters, DJs and acts. @return list<array<string, mixed>> */
    public function people(): array
    {
        $data = $this->shapedGraphQL(Queries::LISTING_TYPES, Queries::people(...), null, 'People');

        return self::nodes($data['people']['list'] ?? null);
    }

    /** The audience's locales. @return list<array<string, mixed>> */
    public function locales(): array
    {
        $data = $this->shapedGraphQL(Queries::LISTING_TYPES, Queries::locales(...), null, 'Locales');
        $locales = $data['locales'] ?? null;

        return is_array($locales) ? array_values(array_filter($locales, 'is_array')) : [];
    }

    /** The locale closest to a point, or null when the audience has none. @return array<string, mixed>|null */
    public function closestLocale(float $latitude, float $longitude): ?array
    {
        $data = $this->shapedGraphQL(
            Queries::LISTING_TYPES,
            Queries::closestLocale(...),
            ['near' => ['latitude' => $latitude, 'longitude' => $longitude]],
            'ClosestLocale',
        );
        $locale = $data['closestLocale'] ?? null;

        return is_array($locale) ? $locale : null;
    }

    /**
     * The audience's events: upcoming (soonest first) or past (`$window` 'UPCOMING' or 'PAST'), for one locale or
     * venue when given.
     *
     * @return list<array<string, mixed>>
     */
    public function events(
        string $window = 'UPCOMING',
        ?string $localeId = null,
        ?string $venueId = null,
        int $first = 100,
    ): array {
        $variables = ['window' => $window, 'first' => $first];
        if ($localeId !== null) {
            $variables['localeId'] = $localeId;
        }
        if ($venueId !== null) {
            $variables['venueId'] = $venueId;
        }
        $data = $this->shapedGraphQL(Queries::EVENT_TYPES, Queries::events(...), $variables, 'Events');

        return self::nodes($data['events']['list'] ?? null);
    }

    /** One event, or null when there is none with that ID. @return array<string, mixed>|null */
    public function event(string $id): ?array
    {
        $data = $this->shapedGraphQL(Queries::EVENT_TYPES, Queries::event(...), ['id' => $id], 'Event');
        $event = $data['events']['event'] ?? null;

        return is_array($event) ? $event : null;
    }

    /** The audience's recurring event series. @return list<array<string, mixed>> */
    public function eventSeries(?string $localeId = null, ?string $venueId = null, int $first = 100): array
    {
        $variables = ['first' => $first];
        if ($localeId !== null) {
            $variables['localeId'] = $localeId;
        }
        if ($venueId !== null) {
            $variables['venueId'] = $venueId;
        }
        $data = $this->shapedGraphQL(Queries::EVENT_TYPES, Queries::eventSeries(...), $variables, 'EventSeries');

        return self::nodes($data['events']['series'] ?? null);
    }

    /**
     * A venue's page: the venue with its description, profile (address, phone, website, social links), chat (whether
     * open, and its latest `$recentMessages` messages) and upcoming events, as far as the audience's modules go.
     * Null when there is no venue with that ID.
     *
     * @return array<string, mixed>|null
     */
    public function venueDetail(string $id, int $recentMessages = 20): ?array
    {
        $data = $this->shapedGraphQL(
            Queries::VENUE_DETAIL_TYPES,
            Queries::venueDetail(...),
            ['id' => $id, 'recentMessages' => $recentMessages],
            'VenueDetail',
        );
        $venue = $data['venues']['venue'] ?? null;

        return is_array($venue) ? $venue : null;
    }

    /** A venue's cover charge tonight, with the viewer's admission if they have one. @return array<string, mixed>|null */
    public function venueCover(string $venueId): ?array
    {
        $data = $this->shapedGraphQL(Queries::VENUE_TICKET_TYPES, Queries::venueCover(...), ['id' => $venueId], 'VenueCover');
        $venue = $data['venues']['venue'] ?? null;

        return is_array($venue) ? $venue : null;
    }

    /** Every way into a venue on a night (`YYYY-MM-DD`; tonight by default). @return list<array<string, mixed>> */
    public function venueOffers(string $venueId, ?string $night = null): array
    {
        $variables = ['id' => $venueId];
        if ($night !== null) {
            $variables['night'] = $night;
        }
        $data = $this->shapedGraphQL(Queries::VENUE_TICKET_TYPES, Queries::venueOffers(...), $variables, 'VenueOffers');

        return self::nodes($data['venues']['venue']['tickets']['offers'] ?? null);
    }

    /** The signed-in user's admissions (cover passes). @return list<array<string, mixed>> */
    public function admissions(): array
    {
        $data = $this->graphQL(Queries::admissions(), null, 'Admissions');

        return self::nodes($data['me']['cover']['admissions'] ?? null);
    }

    /** Starts buying tonight's cover at a venue: the pending admission and the payment provider's keys. @return array<string, mixed> */
    public function buyCover(string $venueId): array
    {
        return self::object($this->graphQL(Queries::buyCover(), ['venueId' => $venueId], 'BuyCover'), 'buyCover');
    }

    /** Pays a pending admission with a payment source the provider issued. @return array<string, mixed> */
    public function payCover(string $admissionId, string $sourceId, ?string $verificationToken = null): array
    {
        $variables = ['admissionId' => $admissionId, 'sourceId' => $sourceId];
        if ($verificationToken !== null) {
            $variables['verificationToken'] = $verificationToken;
        }

        return self::object(self::object($this->graphQL(Queries::payCover(), $variables, 'PayCover'), 'payCover'), 'admission');
    }

    /** Confirms a paid admission. @return array<string, mixed> */
    public function confirmCover(string $admissionId): array
    {
        $data = $this->graphQL(Queries::confirmCover(), ['admissionId' => $admissionId], 'ConfirmCover');

        return self::object(self::object($data, 'confirmCover'), 'admission');
    }

    /** Refunds an admission. @return array<string, mixed> */
    public function refundAdmission(string $admissionId): array
    {
        $data = $this->graphQL(Queries::refundAdmission(), ['admissionId' => $admissionId], 'RefundAdmission');

        return self::object(self::object($data, 'refundAdmission'), 'admission');
    }

    /** Answers an event's RSVP (`$state` 'ATTENDING', 'MAYBE', 'DECLINED', 'UNSURE') and returns the user's answer as stored. */
    public function rsvpEvent(string $eventId, string $state): string
    {
        $data = $this->graphQL(Queries::RSVP_EVENT, ['eventId' => $eventId, 'state' => $state], 'RSVPEvent');
        $mine = $data['rsvpEvent']['event']['rsvp']['mine'] ?? null;
        if (!is_string($mine)) {
            throw AudienceKitException::decoding('The RSVP had no answer.');
        }

        return $mine;
    }

    /**
     * The tribes people can identify with here (`tribes`) and the signed-in user's own (`mine`, each with its
     * `isPrivate` and `tag`).
     *
     * @return array{tribes: list<array<string, mixed>>, mine: list<array<string, mixed>>}
     */
    public function tribes(): array
    {
        $data = $this->graphQL(Queries::TRIBES, null, 'Tribes');
        $tribes = $data['tribes'] ?? null;
        $mine = $data['me']['self']['tribes'] ?? null;

        return [
            'tribes' => is_array($tribes) ? array_values(array_filter($tribes, 'is_array')) : [],
            'mine' => is_array($mine) ? array_values(array_filter($mine, 'is_array')) : [],
        ];
    }

    /** Identifies the signed-in user with a tribe and returns their tribes. @return list<array<string, mixed>> */
    public function identifyWithTribe(string $tagId, ?bool $isPrivate = null): array
    {
        $variables = ['tagId' => $tagId];
        if ($isPrivate !== null) {
            $variables['isPrivate'] = $isPrivate;
        }
        $data = $this->graphQL(Queries::IDENTIFY_WITH_TRIBE, $variables, 'IdentifyWithTribe');

        return self::list(self::object($data, 'identifyWithTribe'), 'tribes');
    }

    /** Removes a tribe from the signed-in user and returns their tribes. @return list<array<string, mixed>> */
    public function leaveTribe(string $tagId): array
    {
        $data = $this->graphQL(Queries::LEAVE_TRIBE, ['tagId' => $tagId], 'LeaveTribe');

        return self::list(self::object($data, 'leaveTribe'), 'tribes');
    }

    /** Registers a push notification token for the signed-in user; true when the API took it. */
    public function registerDevice(string $notificationToken, ?string $appId = null, ?bool $sandbox = null): bool
    {
        $variables = ['notificationToken' => $notificationToken];
        if ($appId !== null) {
            $variables['appId'] = $appId;
        }
        if ($sandbox !== null) {
            $variables['sandbox'] = $sandbox;
        }
        $data = $this->graphQL(Queries::REGISTER_DEVICE, $variables, 'RegisterDevice');

        return ($data['registerDevice']['registered'] ?? false) === true;
    }

    /** Which type a global ID names (`__typename`), or null when there is no such node. */
    public function nodeType(string $id): ?string
    {
        $type = $this->graphQL(Queries::NODE, ['id' => $id], 'Node')['node']['__typename'] ?? null;

        return is_string($type) ? $type : null;
    }

    /**
     * Posts a message as the signed-in user in a venue's or locale's chat room (`$room` is `['venueId' => …]` or
     * `['localeId' => …]`), answering a prompt when `$promptId` is given.
     *
     * @param array<string, string> $room
     * @return array<string, mixed>
     */
    public function sendChatMessage(string $message, array $room, ?string $promptId = null): array
    {
        $input = $room + ['message' => $message];
        if ($promptId !== null) {
            $input['promptId'] = $promptId;
        }
        $data = $this->graphQL(Queries::SEND_CHAT_MESSAGE, ['input' => $input], 'SendMyChatMessage');

        return self::object(self::object($data, 'sendMyChatMessage'), 'message');
    }

    /** Removes one of the signed-in user's own chat messages; returns the removed message's ID. */
    public function removeChatMessage(string $messageId): string
    {
        $data = $this->graphQL(Queries::REMOVE_CHAT_MESSAGE, ['messageId' => $messageId], 'RemoveMyChatMessage');
        $deleted = $data['removeMyChatMessage']['deletedId'] ?? null;

        return is_string($deleted) ? $deleted : $messageId;
    }

    /**
     * The `nodes` of a connection, or an empty list where the module isn't there.
     *
     * @return list<array<string, mixed>>
     */
    private static function nodes(mixed $connection): array
    {
        return is_array($connection) ? self::list($connection, 'nodes') : [];
    }

    /**
     * @param array<string, mixed> $data
     * @return list<array<string, mixed>>
     */
    private static function list(array $data, string $key): array
    {
        $list = $data[$key] ?? null;

        return is_array($list) ? array_values(array_filter($list, 'is_array')) : [];
    }

    /**
     * @param array<string, mixed> $data
     * @return array<string, mixed>
     */
    private static function object(array $data, string $key): array
    {
        $object = $data[$key] ?? null;
        if (!is_array($object)) {
            throw AudienceKitException::decoding("The response had no $key.");
        }

        return $object;
    }
}
