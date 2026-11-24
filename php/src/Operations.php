<?php

declare(strict_types=1);

namespace AudienceKit;

use AudienceKit\Model\Admission;
use AudienceKit\Model\AdmissionOffer;
use AudienceKit\Model\Article;
use AudienceKit\Model\ArticlesPage;
use AudienceKit\Model\Audience;
use AudienceKit\Model\CalendarFeed;
use AudienceKit\Model\ChatMessage;
use AudienceKit\Model\Community;
use AudienceKit\Model\CoverPurchase;
use AudienceKit\Model\Event;
use AudienceKit\Model\EventRSVP;
use AudienceKit\Model\EventSeries;
use AudienceKit\Model\Locale;
use AudienceKit\Model\Person;
use AudienceKit\Model\Publication;
use AudienceKit\Model\PublicListing;
use AudienceKit\Model\PublicListingsPage;
use AudienceKit\Model\ReportResult;
use AudienceKit\Model\SelfUser;
use AudienceKit\Model\Tag;
use AudienceKit\Model\TribeIdentification;
use AudienceKit\Model\Venue;
use AudienceKit\Model\VenueCover;

/**
 * The calls every AudienceKit app makes, so apps are built with little custom code: the same operations the Swift,
 * Kotlin, Node and Python SDKs run, returning models ({@see Model\Model}) with typed properties that are also
 * readable as the API's JSON arrays (keys as the schema names them). Fields a module adds are missing where the
 * audience hasn't installed that module: the SDK asks for them and, if the audience's schema doesn't have one, asks
 * again without.
 */
trait Operations
{
    /** The audience: its name, subdomain and theme. */
    public function audience(): Audience
    {
        return new Audience($this->graphQL(Queries::AUDIENCE, null, 'Audience'));
    }

    /** The signed-in user's own profile (`me { self }`), or null when the API has none (a service token's session). */
    public function me(): ?SelfUser
    {
        return SelfUser::from($this->graphQL(Queries::ME, null, 'Me')['me']['self'] ?? null);
    }

    /** The audience's venues. @return list<Venue> */
    public function venues(): array
    {
        $data = $this->shapedGraphQL(Queries::LISTING_TYPES, Queries::venues(...), null, 'Venues');

        return Venue::list($data['venues']['list'] ?? null);
    }

    /** The audience's people: promoters, DJs and acts. @return list<Person> */
    public function people(): array
    {
        $data = $this->shapedGraphQL(Queries::LISTING_TYPES, Queries::people(...), null, 'People');

        return Person::list($data['people']['list'] ?? null);
    }

    /** The audience's locales. @return list<Locale> */
    public function locales(): array
    {
        $data = $this->shapedGraphQL(Queries::LISTING_TYPES, Queries::locales(...), null, 'Locales');

        return Locale::list($data['locales'] ?? null);
    }

    /**
     * The locale closest to a point (a {@see Coordinate}, or a latitude and a longitude), or null when the audience
     * has none.
     */
    public function closestLocale(Coordinate|float $latitude, ?float $longitude = null): ?Locale
    {
        $near = $latitude instanceof Coordinate ? $latitude : new Coordinate($latitude, $longitude ?? 0.0);
        $data = $this->shapedGraphQL(
            Queries::LISTING_TYPES,
            Queries::closestLocale(...),
            ['near' => $near->toInput()],
            'ClosestLocale',
        );

        return Locale::from($data['closestLocale'] ?? null);
    }

    /**
     * Records the signed-in user's position and says where that is (`venue`, `locale`, `nearbyVenues`, `audience`).
     * Select the fields the app needs, e.g. `'venue { id name } locale { id name }'`, and read the result yourself.
     *
     * @return array<string, mixed>
     */
    public function reportLocation(Coordinate $position, string $fields): array
    {
        $data = $this->graphQL(Queries::reportLocation($fields), ['position' => $position->toInput()], 'ReportLocation');

        return self::object($data, 'reportLocation');
    }

    /**
     * Everything the audience lists, read in one go: the audience, its locales, venues, people, upcoming events and
     * event series. A part whose module the audience doesn't have comes back empty.
     */
    public function community(): Community
    {
        $optional = static function (callable $read): mixed {
            try {
                return $read();
            } catch (AudienceKitException $error) {
                if ($error->isUndefinedField()) {
                    return null;
                }
                throw $error;
            }
        };

        return new Community(
            $optional(fn () => $this->audience()),
            $optional(fn () => $this->locales()) ?? [],
            $optional(fn () => $this->venues()) ?? [],
            $optional(fn () => $this->people()) ?? [],
            $optional(fn () => $this->events()) ?? [],
            $optional(fn () => $this->eventSeries()) ?? [],
        );
    }

    /**
     * The audience's events: upcoming (soonest first) or past (`$window` 'UPCOMING' or 'PAST'), for one locale or
     * venue when given.
     *
     * @return list<Event>
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

        return Event::list($data['events']['list'] ?? null);
    }

    /** One event, or null when there is none with that ID. */
    public function event(string $id): ?Event
    {
        $data = $this->shapedGraphQL(Queries::EVENT_TYPES, Queries::event(...), ['id' => $id], 'Event');

        return Event::from($data['events']['event'] ?? null);
    }

    /** The audience's recurring event series. @return list<EventSeries> */
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

        return EventSeries::list($data['events']['series'] ?? null);
    }

    /**
     * A venue's page: the venue with its description, profile (address, phone, website, social links), chat (whether
     * open, and its latest `$recentMessages` messages) and upcoming events, as far as the audience's modules go.
     * Null when there is no venue with that ID.
     */
    public function venueDetail(string $id, int $recentMessages = 20): ?Venue
    {
        $data = $this->shapedGraphQL(
            Queries::VENUE_DETAIL_TYPES,
            Queries::venueDetail(...),
            ['id' => $id, 'recentMessages' => $recentMessages],
            'VenueDetail',
        );

        return Venue::from($data['venues']['venue'] ?? null);
    }

    /**
     * A venue's cover charge tonight, with the signed-in user's pass and coat check ticket if they have them; null
     * when there is no such venue.
     */
    public function venueCover(string $venueId): ?VenueCover
    {
        $data = $this->shapedGraphQL(Queries::VENUE_TICKET_TYPES, Queries::venueCover(...), ['id' => $venueId], 'VenueCover');

        return VenueCover::from($data['venues']['venue'] ?? null);
    }

    /** Every way into a venue on a night (`YYYY-MM-DD`; tonight by default). @return list<AdmissionOffer> */
    public function venueOffers(string $venueId, ?string $night = null): array
    {
        $variables = ['id' => $venueId];
        if ($night !== null) {
            $variables['night'] = $night;
        }
        $data = $this->shapedGraphQL(Queries::VENUE_TICKET_TYPES, Queries::venueOffers(...), $variables, 'VenueOffers');

        return AdmissionOffer::list($data['venues']['venue']['tickets']['offers'] ?? null);
    }

    /** The signed-in user's admissions (cover passes and coat check tickets), newest first. @return list<Admission> */
    public function admissions(): array
    {
        $data = $this->graphQL(Queries::admissions(), null, 'Admissions');

        return Admission::list($data['me']['cover']['admissions'] ?? null);
    }

    /**
     * Starts buying tonight's cover at a venue: the pending admission and the payment provider's keys. For a Stripe
     * venue, finish the payment with Stripe.js and call {@see confirmCover()}; for a Square venue, make a payment
     * token and call {@see payCover()}. Asking again the same night returns the same pass. On a sliding scale,
     * `$amountCents` is what the buyer chose; left out, the suggested (or fixed) amount.
     */
    public function buyCover(string $venueId, ?int $amountCents = null, string $currency = 'usd'): CoverPurchase
    {
        $variables = ['venueId' => $venueId];
        if ($amountCents !== null) {
            $variables['amount'] = ['cents' => $amountCents, 'currency' => $currency];
        }

        return new CoverPurchase(self::object($this->graphQL(Queries::buyCover(), $variables, 'BuyCover'), 'buyCover'));
    }

    /** Starts paying tonight's coat check at a venue for `$quantity` coats, the same way as {@see buyCover()}. */
    public function buyCoatCheck(string $venueId, int $quantity = 1): CoverPurchase
    {
        $data = $this->graphQL(Queries::buyCoatCheck(), ['venueId' => $venueId, 'quantity' => $quantity], 'BuyCoatCheck');

        return new CoverPurchase(self::object($data, 'buyCoatCheck'));
    }

    /** Pays a Square venue's pending admission with a payment token from Square's Web Payments SDK. */
    public function payCover(string $admissionId, string $sourceId, ?string $verificationToken = null): Admission
    {
        $variables = ['admissionId' => $admissionId, 'sourceId' => $sourceId];
        if ($verificationToken !== null) {
            $variables['verificationToken'] = $verificationToken;
        }
        $data = $this->graphQL(Queries::payCover(), $variables, 'PayCover');

        return new Admission(self::object(self::object($data, 'payCover'), 'admission'));
    }

    /** Confirms a Stripe venue's admission once Stripe has taken the payment. */
    public function confirmCover(string $admissionId): Admission
    {
        $data = $this->graphQL(Queries::confirmCover(), ['admissionId' => $admissionId], 'ConfirmCover');

        return new Admission(self::object(self::object($data, 'confirmCover'), 'admission'));
    }

    /** Refunds an admission that {@see Admission::$isRefundable}. */
    public function refundAdmission(string $admissionId): Admission
    {
        $data = $this->graphQL(Queries::refundAdmission(), ['admissionId' => $admissionId], 'RefundAdmission');

        return new Admission(self::object(self::object($data, 'refundAdmission'), 'admission'));
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
     * Takes back the signed-in user's RSVP, as if they'd never answered, and returns the event's RSVPs afterwards.
     * Someone holding a ticket stays going.
     */
    public function cancelRsvp(string $eventId): EventRSVP
    {
        $data = $this->graphQL(Queries::CANCEL_RSVP, ['eventId' => $eventId], 'CancelRSVP');
        $rsvp = $data['cancelRsvp']['event']['rsvp'] ?? null;
        if (!is_array($rsvp)) {
            throw AudienceKitException::decoding('The response had no rsvp.');
        }

        return new EventRSVP($rsvp);
    }

    /** Who's going to an event and the first `$first` of them, or null when there's no such event. */
    public function eventRsvp(string $eventId, int $first = 50): ?EventRSVP
    {
        $data = $this->graphQL(Queries::EVENT_RSVP, ['id' => $eventId, 'first' => $first], 'EventRSVP');

        return EventRSVP::from($data['events']['event']['rsvp'] ?? null);
    }

    /**
     * The tribes people can identify with here (`tribes`) and the signed-in user's own (`mine`, each with its
     * `isPrivate` and `tag`).
     *
     * @return array{tribes: list<Tag>, mine: list<TribeIdentification>}
     */
    public function tribes(): array
    {
        $data = $this->graphQL(Queries::TRIBES, null, 'Tribes');

        return [
            'tribes' => Tag::list($data['tribes'] ?? null),
            'mine' => TribeIdentification::list($data['me']['self']['tribes'] ?? null),
        ];
    }

    /** Identifies the signed-in user with a tribe and returns their tribes. @return list<TribeIdentification> */
    public function identifyWithTribe(string $tagId, ?bool $isPrivate = null): array
    {
        $variables = ['tagId' => $tagId];
        if ($isPrivate !== null) {
            $variables['isPrivate'] = $isPrivate;
        }
        $data = $this->graphQL(Queries::IDENTIFY_WITH_TRIBE, $variables, 'IdentifyWithTribe');

        return TribeIdentification::list(self::object($data, 'identifyWithTribe')['tribes'] ?? null);
    }

    /** Removes a tribe from the signed-in user and returns their tribes. @return list<TribeIdentification> */
    public function leaveTribe(string $tagId): array
    {
        $data = $this->graphQL(Queries::LEAVE_TRIBE, ['tagId' => $tagId], 'LeaveTribe');

        return TribeIdentification::list(self::object($data, 'leaveTribe')['tribes'] ?? null);
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
     */
    public function sendChatMessage(string $message, array $room, ?string $promptId = null): ChatMessage
    {
        $input = $room + ['message' => $message];
        if ($promptId !== null) {
            $input['promptId'] = $promptId;
        }
        $data = $this->graphQL(Queries::SEND_CHAT_MESSAGE, ['input' => $input], 'SendMyChatMessage');

        return new ChatMessage(self::object(self::object($data, 'sendMyChatMessage'), 'message'));
    }

    /** Removes one of the signed-in user's own chat messages; returns the removed message's ID. */
    public function removeChatMessage(string $messageId): string
    {
        $data = $this->graphQL(Queries::REMOVE_CHAT_MESSAGE, ['messageId' => $messageId], 'RemoveMyChatMessage');
        $deleted = $data['removeMyChatMessage']['deletedId'] ?? null;

        return is_string($deleted) ? $deleted : $messageId;
    }

    // Soapbox (news)

    /**
     * The audience's live articles, pinned first, then newest: a locale's news, or one publication's, when given.
     * Empty when the audience doesn't have Soapbox.
     *
     * @return list<Article>
     */
    public function articles(?string $localeId = null, ?string $publicationId = null, ?int $first = null): array
    {
        $variables = self::compact(['localeId' => $localeId, 'publicationId' => $publicationId, 'first' => $first]);
        $data = $this->shapedGraphQL(Queries::SOAPBOX_TYPES, Queries::articles(...), $variables ?: null, 'Articles');

        return Article::list($data['soapbox']['articles'] ?? null);
    }

    /**
     * A page of the audience's live articles, pinned first, then newest, for lists that "Show more". Pass the last
     * page's {@see ArticlesPage::$endCursor} as `$after` for the next.
     */
    public function articlesPage(
        ?string $localeId = null,
        ?string $publicationId = null,
        int $first = 20,
        ?string $after = null,
    ): ArticlesPage {
        $variables = self::compact([
            'localeId' => $localeId, 'publicationId' => $publicationId, 'first' => $first, 'after' => $after,
        ]);
        $data = $this->shapedGraphQL(Queries::SOAPBOX_TYPES, Queries::articlesPage(...), $variables, 'ArticlesPage');

        return ArticlesPage::fromConnection($data['soapbox']['articles'] ?? null);
    }

    /**
     * The audience's national news: articles its admins featured nationally in the last 14 days, most recently
     * featured first (a locale's share of it, when given). Empty before the API had national news.
     *
     * @return list<Article>
     */
    public function nationalArticles(?string $localeId = null, ?int $first = null): array
    {
        $variables = self::compact(['localeId' => $localeId, 'first' => $first]);
        $data = $this->shapedGraphQL(
            Queries::SOAPBOX_TYPES,
            Queries::nationalArticles(...),
            $variables ?: null,
            'NationalArticles',
        );

        return Article::list($data['soapbox']['articles'] ?? null);
    }

    /** One article with its body and what it's about; null when there's none, or the audience has no Soapbox. */
    public function article(string $id): ?Article
    {
        $data = $this->shapedGraphQL(Queries::SOAPBOX_TYPES, Queries::article(...), ['id' => $id], 'Article');

        return Article::from($data['soapbox']['article'] ?? null);
    }

    /**
     * Live articles about a venue, event or person, newest first, or a locale's news ("In the news"). `$topic` is
     * 'venue', 'event', 'person' or 'locale'.
     *
     * @return list<Article>
     */
    public function articlesAbout(string $topic, string $id, ?int $first = null): array
    {
        [$type, $document] = Queries::articlesAbout($topic);
        $data = $this->shapedGraphQL(
            [...Queries::SOAPBOX_TYPES, $type],
            $document,
            self::compact(['id' => $id, 'first' => $first]),
            'ArticlesAbout',
        );
        $listing = $data['venues']['venue'] ?? $data['events']['event'] ?? $data['people']['person'] ?? $data['locale'] ?? null;

        return Article::list(is_array($listing) ? ($listing['articles']['list'] ?? null) : null);
    }

    /** The audience's publications. @return list<Publication> */
    public function publications(): array
    {
        $data = $this->shapedGraphQL(Queries::SOAPBOX_TYPES, Queries::publications(...), null, 'Publications');

        return Publication::list($data['soapbox']['publications'] ?? null);
    }

    /** The publications covering a locale, the "local publishers" at the top of its news. @return list<Publication> */
    public function localPublications(string $localeId): array
    {
        return array_values(array_filter(
            $this->publications(),
            static fn (Publication $publication) => strcasecmp($publication->locale?->id ?? '', $localeId) === 0,
        ));
    }

    /** One publication, for its page and its "Write an op-ed" button. */
    public function publication(string $id): ?Publication
    {
        $data = $this->shapedGraphQL(Queries::SOAPBOX_TYPES, Queries::publication(...), ['id' => $id], 'Publication');

        return Publication::from($data['soapbox']['publication'] ?? null);
    }

    /** The op-eds the signed-in person sent, newest first, with their status and the publication's note. @return list<Article> */
    public function myOpEds(): array
    {
        $data = $this->shapedGraphQL(Queries::SOAPBOX_TYPES, Queries::myOpEds(...), null, 'MyOpEds');

        return Article::list($data['soapbox']['myOpEds'] ?? null);
    }

    /**
     * Sends a publication an op-ed under the signed-in person's name (`$byline` overrides it). The publication runs it
     * or declines it with a note; {@see myOpEds()} shows which. Only a publication that accepts op-eds takes them.
     */
    public function submitOpEd(
        string $publicationId,
        string $title,
        string $body,
        ?string $summary = null,
        ?string $byline = null,
    ): Article {
        $variables = [
            'publicationId' => $publicationId, 'title' => $title, 'body' => $body,
            'summary' => $summary, 'byline' => $byline,
        ];
        $data = $this->graphQL(Queries::submitOpEd(), $variables, 'SubmitOpEd');

        return new Article(self::object(self::object($data, 'submitOpEd'), 'article'));
    }

    // Calendar subscription

    /** The signed-in person's calendar subscription, or null before they made one. */
    public function calendarFeed(): ?CalendarFeed
    {
        return CalendarFeed::from($this->graphQL(Queries::calendarFeed(), null, 'CalendarFeed')['me']['calendarFeed'] ?? null);
    }

    /** Their subscription, made on first ask; `$reset` gives it a new link, so the old one stops working. */
    public function createCalendarFeed(bool $reset = false): CalendarFeed
    {
        $data = $this->graphQL(Queries::createCalendarFeed(), ['reset' => $reset], 'CreateCalendarFeed');

        return new CalendarFeed(self::object(self::object($data, 'createCalendarFeed'), 'calendarFeed'));
    }

    /**
     * Follows a venue in their subscription, so every event there shows up in their calendar (or, with
     * `$following` false, stops). Makes the subscription on first ask.
     */
    public function followVenueInCalendar(string $venueId, bool $following = true): CalendarFeed
    {
        $data = $this->graphQL(
            Queries::setCalendarFeedVenue(),
            ['venueId' => $venueId, 'following' => $following],
            'SetCalendarFeedVenue',
        );

        return new CalendarFeed(self::object(self::object($data, 'setCalendarFeedVenue'), 'calendarFeed'));
    }

    /** Ends their subscription: calendars subscribed to it stop updating. */
    public function deleteCalendarFeed(): bool
    {
        $data = $this->graphQL(Queries::DELETE_CALENDAR_FEED, null, 'DeleteCalendarFeed');

        return ($data['deleteCalendarFeed']['deleted'] ?? false) === true;
    }

    // Moderation

    /**
     * Files a report with the audience's admins (App Store guideline 1.2, Google Play's user-generated content
     * policy). `$targetType` is one of {@see ReportTarget}'s constants; with `$block`, the person behind it is
     * blocked too. Offer {@see ReportTarget::REASONS} as reasons.
     */
    public function reportContent(string $targetType, string $id, ?string $reason = null, bool $block = false): ReportResult
    {
        $data = $this->graphQL(
            Queries::REPORT_CONTENT,
            ['targetType' => $targetType, 'targetId' => $id, 'reason' => $reason, 'block' => $block],
            'ReportContent',
        );
        $result = $data['reportContent'] ?? [];

        return new ReportResult(($result['reported'] ?? false) === true, ($result['blocked'] ?? false) === true);
    }

    /** Blocks a member (their user ID): they and the signed-in person stop seeing each other's messages. */
    public function blockUser(string $userId): void
    {
        $this->graphQL(Queries::BLOCK_USER, ['userId' => $userId], 'BlockUser');
    }

    /** Unblocks a member blocked with {@see blockUser()} or a report. */
    public function unblockUser(string $userId): void
    {
        $this->graphQL(Queries::UNBLOCK_USER, ['userId' => $userId], 'UnblockUser');
    }

    // Public listings (REST)

    /**
     * One page (from 1) of the audience's public listings: up to 500 venues, then events, then posts, as its
     * websites show them. Needs a service token with the `public:read` scope ({@see AudienceSession::useServiceToken()}).
     */
    public function publicListingsPage(int $page = 1): PublicListingsPage
    {
        $body = $this->request(new ApiRequest('/v1/public/listings', query: ['page' => max(1, $page)]));

        return PublicListingsPage::fromArray($this->decodeObject($body));
    }

    /** Every public listing, page by page. @return list<PublicListing> */
    public function publicListings(): array
    {
        $listings = [];
        $page = 1;
        while (true) {
            $found = $this->publicListingsPage($page);
            array_push($listings, ...$found->listings);
            if ($found->nextPage === null || $found->nextPage <= $page) {
                return $listings;
            }
            $page = $found->nextPage;
        }
    }

    /** One public listing (`$kind` 'venue', 'event' or 'post'), or null when there's none. */
    public function publicListing(string $kind, string $id): ?PublicListing
    {
        $path = match ($kind) {
            'venue' => 'venues',
            'event' => 'events',
            'post' => 'posts',
            default => throw new \InvalidArgumentException("A listing is a venue, event or post, not $kind."),
        };
        try {
            $body = $this->request(new ApiRequest("/v1/public/$path/" . rawurlencode($id)));
        } catch (AudienceKitException $error) {
            if ($error->errorCode === AudienceKitException::CODE_NOT_FOUND) {
                return null;
            }
            throw $error;
        }

        return PublicListing::from($this->decodeObject($body));
    }

    /** Tonight at a venue, as a screen facing the room shows it (`GET /v1/public/venues/<id>/tonight`). @return array<string, mixed> */
    public function publicTonight(string $venueId): array
    {
        return $this->decodeObject($this->request(new ApiRequest('/v1/public/venues/' . rawurlencode($venueId) . '/tonight')));
    }

    /**
     * `$values` without the nulls, for variables a document declares as optional.
     *
     * @param array<string, mixed> $values
     * @return array<string, mixed>
     */
    private static function compact(array $values): array
    {
        return array_filter($values, static fn ($value) => $value !== null);
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
