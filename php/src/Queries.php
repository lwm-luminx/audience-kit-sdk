<?php

declare(strict_types=1);

namespace AudienceKit;

/**
 * The GraphQL documents behind {@see AudienceSession}'s helpers: the same operations the Swift and Kotlin SDKs run.
 * Documents with module fields take the audience's {@see SchemaShape}: the API leaves a module's fields out of an
 * audience that hasn't installed it, and asking for one fails the whole operation.
 *
 * Apps run their own operations through {@see AudienceSession::graphQL()}; these are for what every app shows.
 */
final class Queries
{
    public const PAGE_FIELDS = 'id name photoUrl bannerUrl';
    /** A tag on a venue, person or event: its name and chip color. */
    public const TAG_FIELDS = 'id name color';
    public const MONEY_FIELDS = 'cents currency';
    public const PROFILE_FIELDS = 'id name avatarUrl';
    /** A cover charge: the amount, fee and total, its coat check, and on a sliding scale the range to pick from. */
    public const COVER_CHARGE_FIELDS = 'amount { cents currency } total { cents currency } fee { cents currency }'
        . ' night from payable event { id name }'
        . ' coatCheck { amount { cents currency } fee { cents currency } total { cents currency } night payable }'
        . ' scale { min { cents currency } max { cents currency } suggested { cents currency } }';
    /** An admission: the pass secret the buyer makes the QR code from, and the buyer's profile for the door. */
    public const ADMISSION_FIELDS = 'id status kind night quantity tier claimCheckNumber amount { cents currency }'
        . ' fee { cents currency } total { cents currency } isRefundable passSecret scanCount checkedInAt createdAt'
        . ' profile { id name avatarUrl } venue { id name photoUrl } event { id name }';
    /** An event's rsvp mixin for the signed-in user: how many are going, and their own answer and why. */
    public const RSVP_FIELDS = 'count mine mineSource';
    public const EVENT_ATTENDEE_FIELDS = 'profile { id name avatarUrl } friend source';
    public const ADMISSION_OFFER_FIELDS = 'price { cents currency } url seller { key name }';
    public const CHAT_MESSAGE_FIELDS = 'id body message name userId avatarUrl photoUrl sentAt role kind title pinned';

    /** The types whose fields the listing documents depend on. */
    public const LISTING_TYPES = ['Locale', 'ListingProfile', 'Venue', 'Location', 'Person', 'Event'];
    /** The types the event documents depend on. */
    public const EVENT_TYPES = [...self::LISTING_TYPES, 'EventSeries', 'EventTickets', 'EventPeopleView'];
    /** The types `venueCover` and `venueOffers` depend on. */
    public const VENUE_TICKET_TYPES = ['Venue', 'VenueTickets'];
    public const VENUE_DETAIL_TYPES = self::EVENT_TYPES;
    /** The types the Soapbox documents depend on: the root's `soapbox` and each listing's `articles`. */
    public const SOAPBOX_TYPES = ['Audience', 'Venue', 'Event', 'Person', 'Locale', 'Article', 'Publication'];

    public const PUBLICATION_SUMMARY_FIELDS = 'id name photoUrl trusted acceptsOpEds';
    public const ARTICLE_FIELDS = 'id slug title summary byline kind publishedAt edited pinned teaser canonicalUrl'
        . ' disclosure heroPhotoUrl heroAltText publication { ' . self::PUBLICATION_SUMMARY_FIELDS . ' }';
    public const ARTICLE_SUBJECT_FIELDS = 'venues { id name } events { id name } people { id name } locales { id name }';
    public const PUBLICATION_FIELDS = 'id name masthead about websiteUrl photoUrl trusted acceptsOpEds opEdGuidelines'
        . ' locale { id name } person { id name }';
    public const CALENDAR_FEED_FIELDS = 'url webcalUrl googleUrl venues { id }';

    public const AUDIENCE = <<<'GRAPHQL'
        query Audience {
          id name subdomain theme { preset tagline light { name value } dark { name value } }
        }
        GRAPHQL;

    public const ME = <<<'GRAPHQL'
        query Me {
          me { self { id name firstName lastName emailAddress isAdmin presence } }
        }
        GRAPHQL;

    public const RSVP_EVENT = <<<'GRAPHQL'
        mutation RSVPEvent($eventId: ID!, $state: RSVPState!) {
          rsvpEvent(input: { eventId: $eventId, state: $state }) { event { id rsvp { count mine mineSource } } }
        }
        GRAPHQL;

    /** Takes back the signed-in user's RSVP, as if they'd never answered. */
    public const CANCEL_RSVP = <<<'GRAPHQL'
        mutation CancelRSVP($eventId: ID!) {
          cancelRsvp(input: { eventId: $eventId }) { event { id rsvp { count mine mineSource } } }
        }
        GRAPHQL;

    /** Who's going to an event: the counts (staff-only ones too) and the first `$first` attendees. */
    public const EVENT_RSVP = <<<'GRAPHQL'
        query EventRSVP($id: ID!, $first: Int) {
          events {
            event(id: $id) {
              id
              rsvp {
                count mine mineSource counts { going interested tickets }
                attendees(first: $first) { nodes { profile { id name avatarUrl } friend source } }
              }
            }
          }
        }
        GRAPHQL;

    /** The tribes people can identify with here, and the signed-in user's own. */
    public const TRIBES = <<<'GRAPHQL'
        query Tribes {
          id tribes: tags(tribes: true) { id name color tribe }
          me { self { id tribes { isPrivate tag { id name color tribe } } } }
        }
        GRAPHQL;

    public const IDENTIFY_WITH_TRIBE = <<<'GRAPHQL'
        mutation IdentifyWithTribe($tagId: ID!, $isPrivate: Boolean) {
          identifyWithTribe(input: { tagId: $tagId, isPrivate: $isPrivate }) {
            tribes { isPrivate tag { id name color tribe } }
          }
        }
        GRAPHQL;

    public const LEAVE_TRIBE = <<<'GRAPHQL'
        mutation LeaveTribe($tagId: ID!) {
          leaveTribe(input: { tagId: $tagId }) { tribes { isPrivate tag { id name color tribe } } }
        }
        GRAPHQL;

    public const REGISTER_DEVICE = <<<'GRAPHQL'
        mutation RegisterDevice($notificationToken: String!, $appId: String, $sandbox: Boolean) {
          registerDevice(input: { notificationToken: $notificationToken, appId: $appId, sandbox: $sandbox }) { registered }
        }
        GRAPHQL;

    public const NODE = <<<'GRAPHQL'
        query Node($id: ID!) {
          node(id: $id) { __typename id }
        }
        GRAPHQL;

    public const SEND_CHAT_MESSAGE = <<<'GRAPHQL'
        mutation SendMyChatMessage($input: ChatMessageSendOwnInput!) {
          sendMyChatMessage(input: $input) { message { id body message name userId avatarUrl photoUrl sentAt role kind title pinned } }
        }
        GRAPHQL;

    public const REMOVE_CHAT_MESSAGE = <<<'GRAPHQL'
        mutation RemoveMyChatMessage($messageId: ID!) {
          removeMyChatMessage(input: { messageId: $messageId }) { deletedId }
        }
        GRAPHQL;

    /** Deletes the signed-in person's account for good. */
    public const DELETE_ACCOUNT = <<<'GRAPHQL'
        mutation DeleteAccount($confirm: Boolean!) {
          deleteAccount(input: { confirm: $confirm }) { deleted }
        }
        GRAPHQL;

    /** Files a report with the audience's admins, blocking the person behind it when `$block`. */
    public const REPORT_CONTENT = <<<'GRAPHQL'
        mutation ReportContent($targetType: ReportTarget!, $targetId: ID!, $reason: String, $block: Boolean) {
          reportContent(input: { targetType: $targetType, targetId: $targetId, reason: $reason, block: $block }) {
            reported
            blocked
          }
        }
        GRAPHQL;

    public const BLOCK_USER = <<<'GRAPHQL'
        mutation BlockUser($userId: ID!) {
          blockUser(input: { userId: $userId }) { blockedUsers { id } }
        }
        GRAPHQL;

    public const UNBLOCK_USER = <<<'GRAPHQL'
        mutation UnblockUser($userId: ID!) {
          unblockUser(input: { userId: $userId }) { blockedUsers { id } }
        }
        GRAPHQL;

    public const DELETE_CALENDAR_FEED = <<<'GRAPHQL'
        mutation DeleteCalendarFeed {
          deleteCalendarFeed(input: {}) { deleted }
        }
        GRAPHQL;

    public static function calendarFeed(): string
    {
        return "query CalendarFeed {\n  me { calendarFeed { " . self::CALENDAR_FEED_FIELDS . " } }\n}";
    }

    public static function createCalendarFeed(): string
    {
        return "mutation CreateCalendarFeed(\$reset: Boolean) {\n"
            . '  createCalendarFeed(input: { reset: $reset }) { calendarFeed { ' . self::CALENDAR_FEED_FIELDS . " } }\n}";
    }

    public static function setCalendarFeedVenue(): string
    {
        return "mutation SetCalendarFeedVenue(\$venueId: ID!, \$following: Boolean) {\n"
            . '  setCalendarFeedVenue(input: { venueId: $venueId, following: $following }) { calendarFeed { '
            . self::CALENDAR_FEED_FIELDS . " } }\n}";
    }

    /**
     * Records the user's position and says where that is: `venue` when they're in one, else `locale` and its
     * `nearbyVenues`, plus `audience` for its mixins. Select the fields the app needs (`$fields`); `$position` is a
     * {@see Coordinate::toInput()}.
     */
    public static function reportLocation(string $fields): string
    {
        return "mutation ReportLocation(\$position: CoordinatesInput!) {\n"
            . '  reportLocation(input: { position: $position }) { ' . $fields . " }\n}";
    }

    /**
     * A chat room's subscription (`$kind` 'venue' or 'locale'), aliased to `room` whichever field it is, for an app
     * with its own Action Cable client. With `$watch`, a staff member watches without joining.
     */
    public static function chatRoom(string $kind, bool $watch = false): string
    {
        $field = $kind === 'venue' ? 'venueChat' : 'localeChat';
        $argument = $kind === 'venue' ? 'venueId' : 'localeId';

        return "subscription ChatRoom(\$id: ID!) {\n"
            . "  room: $field($argument: \$id" . ($watch ? ', watch: true' : '') . ") {\n"
            . "    __typename\n"
            . "    ... on ChatJoined {\n"
            . "      outOfRange\n"
            . "      roster { people { userId name avatarUrl friend } }\n"
            . "      history { message { ...Line } }\n"
            . "      pinnedMessage { message { ...Line } }\n"
            . "    }\n"
            . "    ... on ChatMessagePosted { message { ...Line } }\n"
            . "    ... on ChatMessageUpdated { message { ...Line } }\n"
            . "    ... on ChatMessageRemoved { messageId }\n"
            . "    ... on ChatPinChanged { messageId pinned announcement { ...Line } }\n"
            . "    ... on ChatRoomCleared { clearedAt expired }\n"
            . "    ... on ChatPresenceChanged { userId name avatarUrl presence }\n"
            . "    ... on ChatRangeChanged { outOfRange }\n"
            . "    ... on ChatLeft { reason }\n"
            . "  }\n"
            . "}\n"
            . 'fragment Line on ChatMessage { ' . self::CHAT_MESSAGE_FIELDS . ' }';
    }

    public static function admissions(): string
    {
        return "query Admissions {\n  me { cover { admissions { nodes { " . self::ADMISSION_FIELDS . " } } } }\n}";
    }

    private const PURCHASE_FIELDS = 'provider paymentIntentClientSecret publishableKey stripeAccountId'
        . ' squareApplicationId squareLocationId';

    public static function buyCover(): string
    {
        return "mutation BuyCover(\$venueId: ID!, \$amount: MoneyInput) {\n"
            . "  buyCover(input: { venueId: \$venueId, amount: \$amount }) {\n"
            . '    admission { ' . self::ADMISSION_FIELDS . " }\n"
            . '    ' . self::PURCHASE_FIELDS . "\n"
            . "  }\n}";
    }

    public static function buyCoatCheck(): string
    {
        return "mutation BuyCoatCheck(\$venueId: ID!, \$quantity: Int) {\n"
            . "  buyCoatCheck(input: { venueId: \$venueId, quantity: \$quantity }) {\n"
            . '    admission { ' . self::ADMISSION_FIELDS . " }\n"
            . '    ' . self::PURCHASE_FIELDS . "\n"
            . "  }\n}";
    }

    public static function payCover(): string
    {
        return "mutation PayCover(\$admissionId: ID!, \$sourceId: String!, \$verificationToken: String) {\n"
            . "  payCover(input: { admissionId: \$admissionId, sourceId: \$sourceId, verificationToken: \$verificationToken }) {\n"
            . '    admission { ' . self::ADMISSION_FIELDS . " }\n  }\n}";
    }

    public static function confirmCover(): string
    {
        return "mutation ConfirmCover(\$admissionId: ID!) {\n"
            . '  confirmCover(input: { admissionId: $admissionId }) { admission { ' . self::ADMISSION_FIELDS . " } }\n}";
    }

    public static function refundAdmission(): string
    {
        return "mutation RefundAdmission(\$admissionId: ID!) {\n"
            . '  refundAdmission(input: { admissionId: $admissionId }) { admission { ' . self::ADMISSION_FIELDS . " } }\n}";
    }

    // Shaped documents.

    /** A locale, with its Google place ID (Listings and Google Places). */
    public static function localeFields(SchemaShape $shape): string
    {
        return 'id name label cityNames bannerUrl'
            . ($shape->has('Locale', 'profile') && $shape->has('ListingProfile', 'places')
                ? ' profile { places { placeId } }' : '');
    }

    /** A venue in a list: its Facebook Page (Listings and Facebook) and its location's Google place ID. */
    public static function venueFields(SchemaShape $shape): string
    {
        $page = $shape->has('Venue', 'profile') && $shape->has('ListingProfile', 'facebook')
            ? ' profile { facebook { page { ' . self::PAGE_FIELDS . ' } } }' : '';
        $place = $shape->has('Location', 'places') ? ' places { placeId }' : '';

        return 'id name hidden order photoUrl bannerUrl' . $page
            . ' locale { ' . self::localeFields($shape) . ' }'
            . ' location { id point address' . $place . ' }'
            . ' tags { ' . self::TAG_FIELDS . ' }';
    }

    /** A person's home venue or gig venue, and which of the signed-in user's friends are there now (Friends). */
    public static function personVenueFields(SchemaShape $shape): string
    {
        return 'id name photoUrl locale { id name }' . ($shape->has('Venue', 'friends')
            ? ' friends { list { nodes { id name facebookId presence } } }' : '');
    }

    /** One of a person's events (`PersonEvent`). */
    public static function personEventFields(SchemaShape $shape): string
    {
        return 'id name startAt locale { id name }'
            . ($shape->has('Event', 'venue')
                ? ' venue { name venue { ' . self::personVenueFields($shape) . ' } }' : '')
            . ' tags { ' . self::TAG_FIELDS . ' }';
    }

    public static function venues(SchemaShape $shape): string
    {
        return "query Venues {\n  venues { list { nodes { " . self::venueFields($shape) . " } } }\n}";
    }

    public static function people(SchemaShape $shape): string
    {
        $page = $shape->has('Person', 'profile') && $shape->has('ListingProfile', 'facebook')
            ? ' profile { facebook { page { ' . self::PAGE_FIELDS . ' } } }' : '';
        $venues = $shape->has('Person', 'venues')
            ? ' venues { home { ' . self::personVenueFields($shape) . ' } }' : '';
        $events = $shape->has('Person', 'events')
            ? ' events { involvements { edges { relationship role via { id name } node { '
                . self::personEventFields($shape) . ' } } } }'
            : '';

        return "query People {\n  people { list { nodes { id name avatarUrl bannerUrl order global likeRequired"
            . $page . $venues . ' locales { id name }' . $events . ' tags { ' . self::TAG_FIELDS . " } } } }\n}";
    }

    public static function locales(SchemaShape $shape): string
    {
        return "query Locales {\n  locales { " . self::localeFields($shape) . " }\n}";
    }

    public static function closestLocale(SchemaShape $shape): string
    {
        return "query ClosestLocale(\$near: CoordinatesInput!) {\n  closestLocale(near: \$near) { "
            . self::localeFields($shape) . " }\n}";
    }

    /** A venue's cover tonight, or just the venue where the audience doesn't have the Ticketing and Cover modules. */
    public static function venueCover(SchemaShape $shape): string
    {
        $cover = $shape->has('Venue', 'tickets') && $shape->has('VenueTickets', 'cover')
            ? ' tickets { cover { charge { ' . self::COVER_CHARGE_FIELDS . ' } viewerAdmission { '
                . self::ADMISSION_FIELDS . ' } viewerCoatCheck { ' . self::ADMISSION_FIELDS . ' } } }'
            : '';

        return "query VenueCover(\$id: ID!) {\n  venues { venue(id: \$id) { id name" . $cover . " } }\n}";
    }

    /** Every way into a venue on a night, or just the venue where the audience doesn't have the Ticketing module. */
    public static function venueOffers(SchemaShape $shape): string
    {
        // A variable the document doesn't use is an error, so $night goes with the field.
        $hasTickets = $shape->has('Venue', 'tickets');
        $offers = $hasTickets
            ? ' tickets { offers(night: $night) { nodes { ' . self::ADMISSION_OFFER_FIELDS . ' } } }' : '';

        return 'query VenueOffers($id: ID!' . ($hasTickets ? ', $night: ISO8601Date' : '') . ") {\n"
            . '  venues { venue(id: $id) { id' . $offers . " } }\n}";
    }

    /** The Ticketing module's part of an event, with the Cover module's charge when the audience has it. */
    public static function eventTicketsFields(SchemaShape $shape): string
    {
        $cover = $shape->has('EventTickets', 'cover') ? ' cover { charge { ' . self::COVER_CHARGE_FIELDS . ' } }' : '';

        return 'tickets { url offers { nodes { ' . self::ADMISSION_OFFER_FIELDS . ' } }' . $cover . ' }';
    }

    /** The Venues module's part of an event or series: a display name and the venue. */
    public static function eventVenueFields(SchemaShape $shape): string
    {
        $place = $shape->has('Location', 'places') ? ' places { placeId }' : '';

        return 'venue { name venue { id name photoUrl location { id point address' . $place . ' } } }';
    }

    /** An event: its own fields, then those of the Venues, RSVP, People and Ticketing modules the audience has. */
    public static function eventFields(SchemaShape $shape): string
    {
        $fields = 'id name description startAt endAt isFeatured isCanceled bannerUrl sourceUrl'
            . ' locale { ' . self::localeFields($shape) . ' } tags { ' . self::TAG_FIELDS . ' }';
        if ($shape->has('Event', 'venue')) {
            $fields .= ' ' . self::eventVenueFields($shape);
        }
        if ($shape->has('Event', 'rsvp')) {
            $fields .= ' rsvp { mine count }';
        }
        if ($shape->has('Event', 'people')) {
            // Its KJ, DJ or VJ: an API from audience_kit_api #881 on.
            $jockeys = $shape->has('EventPeopleView', 'jockeys')
                ? ' jockeys { nodes { id name avatarUrl } } jockeyLabel' : '';
            $fields .= ' people { hosts { nodes { id name avatarUrl } } lineup { nodes { id name avatarUrl } }'
                . $jockeys . ' }';
        }
        if ($shape->has('Event', 'tickets')) {
            $fields .= ' ' . self::eventTicketsFields($shape);
        }

        return $fields;
    }

    public static function eventSeriesFields(SchemaShape $shape): string
    {
        return 'id name description recurrenceText startsOn startTime timeZone durationMinutes bannerUrl'
            . ' locale { ' . self::localeFields($shape) . ' } tags { ' . self::TAG_FIELDS . ' }'
            . ($shape->has('EventSeries', 'venue') ? ' ' . self::eventVenueFields($shape) : '');
    }

    public static function events(SchemaShape $shape): string
    {
        return "query Events(\$window: EventWindow, \$localeId: ID, \$venueId: ID, \$first: Int) {\n"
            . "  events { list(window: \$window, localeId: \$localeId, venueId: \$venueId, first: \$first) {\n"
            . '    nodes { ' . self::eventFields($shape) . " }\n  } }\n}";
    }

    public static function event(SchemaShape $shape): string
    {
        return "query Event(\$id: ID!) {\n  events { event(id: \$id) { " . self::eventFields($shape) . " } }\n}";
    }

    public static function eventSeries(SchemaShape $shape): string
    {
        return "query EventSeries(\$localeId: ID, \$venueId: ID, \$first: Int) {\n"
            . "  events { series(localeId: \$localeId, venueId: \$venueId, first: \$first) { nodes { "
            . self::eventSeriesFields($shape) . " } } }\n}";
    }

    /** A venue's page: the venue and what the modules its audience has add to it. */
    public static function venueDetail(SchemaShape $shape): string
    {
        $fields = self::venueFields($shape) . ' description';
        if ($shape->has('Venue', 'profile')) {
            $fields .= ' profile { address phone website socialLinks { nodes { id handle provider url } } }';
        }
        $hasChat = $shape->has('Venue', 'chat');
        if ($hasChat) {
            $fields .= ' chat { open recentMessages(limit: $recentMessages) { nodes { '
                . self::CHAT_MESSAGE_FIELDS . ' } } }';
        }
        if ($shape->has('Venue', 'events')) {
            $fields .= ' events { upcoming(first: 20) { nodes { ' . self::eventFields($shape) . ' } } }';
        }

        return 'query VenueDetail($id: ID!' . ($hasChat ? ', $recentMessages: Int' : '') . ") {\n"
            . '  venues { venue(id: $id) { ' . $fields . " } }\n}";
    }

    // Soapbox (news)

    /** The article fields this audience's API has: the tip to read without ads came later. */
    public static function articleFields(SchemaShape $shape): string
    {
        if (!$shape->has('Article', 'viewerAdFree') || !$shape->has('Publication', 'adFreeOffered')) {
            return self::ARTICLE_FIELDS;
        }

        return str_replace(
            self::PUBLICATION_SUMMARY_FIELDS,
            self::PUBLICATION_SUMMARY_FIELDS . ' adFreeOffered',
            self::ARTICLE_FIELDS,
        ) . ' viewerAdFree';
    }

    public static function publicationFields(SchemaShape $shape): string
    {
        return self::PUBLICATION_FIELDS . ($shape->has('Publication', 'adFreeOffered')
            ? ' adFreeOffered adFreeTipCents adFreeDays viewerAdFree viewerAdFreeUntil' : '');
    }

    /** The document when the audience has no Soapbox: asks for nothing the helpers read, under the operation's name. */
    public static function noSoapbox(string $name): string
    {
        return "query $name { id }";
    }

    public static function articles(SchemaShape $shape): string
    {
        if (!$shape->has('Audience', 'soapbox')) {
            return self::noSoapbox('Articles');
        }

        return "query Articles(\$localeId: ID, \$publicationId: ID, \$first: Int) {\n"
            . "  soapbox { articles(localeId: \$localeId, publicationId: \$publicationId, first: \$first) {\n"
            . '    nodes { ' . self::articleFields($shape) . " }\n  } }\n}";
    }

    /** A page of the audience's live articles (pinned first, then newest), for lists that load more. */
    public static function articlesPage(SchemaShape $shape): string
    {
        if (!$shape->has('Audience', 'soapbox')) {
            return self::noSoapbox('ArticlesPage');
        }

        return "query ArticlesPage(\$localeId: ID, \$publicationId: ID, \$first: Int, \$after: String) {\n"
            . "  soapbox { articles(localeId: \$localeId, publicationId: \$publicationId, first: \$first, after: \$after) {\n"
            . '    nodes { ' . self::articleFields($shape) . " }\n"
            . "    pageInfo { endCursor hasNextPage }\n  } }\n}";
    }

    /** The audience's national news; an API from before national news gets a document that asks for none. */
    public static function nationalArticles(SchemaShape $shape): string
    {
        if (!$shape->has('Audience', 'soapbox') || !$shape->has('Article', 'featuredNationally')) {
            return self::noSoapbox('NationalArticles');
        }

        return "query NationalArticles(\$localeId: ID, \$first: Int) {\n"
            . "  soapbox { articles(national: true, localeId: \$localeId, first: \$first) {\n"
            . '    nodes { ' . self::articleFields($shape) . " featuredNationally }\n  } }\n}";
    }

    public static function article(SchemaShape $shape): string
    {
        if (!$shape->has('Audience', 'soapbox')) {
            return self::noSoapbox('Article');
        }

        return "query Article(\$id: ID!) {\n  soapbox { article(id: \$id) { " . self::articleFields($shape)
            . ' body ' . self::ARTICLE_SUBJECT_FIELDS . " } }\n}";
    }

    public static function publications(SchemaShape $shape): string
    {
        if (!$shape->has('Audience', 'soapbox')) {
            return self::noSoapbox('Publications');
        }

        return "query Publications {\n  soapbox { publications { " . self::publicationFields($shape) . " } }\n}";
    }

    public static function publication(SchemaShape $shape): string
    {
        if (!$shape->has('Audience', 'soapbox')) {
            return self::noSoapbox('Publication');
        }

        return "query Publication(\$id: ID!) {\n  soapbox { publication(id: \$id) { "
            . self::publicationFields($shape) . " } }\n}";
    }

    public static function myOpEds(SchemaShape $shape): string
    {
        if (!$shape->has('Audience', 'soapbox')) {
            return self::noSoapbox('MyOpEds');
        }

        return "query MyOpEds {\n  soapbox { myOpEds { " . self::ARTICLE_FIELDS . " status reviewNote submittedAt } }\n}";
    }

    /**
     * Live articles about a venue, event, person or locale (`$topic` 'venue', 'event', 'person' or 'locale'): the
     * listing type the document depends on, and the document.
     *
     * @return array{string, callable(SchemaShape): string}
     */
    public static function articlesAbout(string $topic): array
    {
        [$type, $open, $close] = match ($topic) {
            'venue' => ['Venue', 'venues { venue(id: $id) { ', ' } }'],
            'event' => ['Event', 'events { event(id: $id) { ', ' } }'],
            'person' => ['Person', 'people { person(id: $id) { ', ' } }'],
            'locale' => ['Locale', 'locale(id: $id) { ', ' }'],
            default => throw new \InvalidArgumentException("Articles are about a venue, event, person or locale, not $topic."),
        };

        return [$type, static function (SchemaShape $shape) use ($type, $open, $close): string {
            if (!$shape->has($type, 'articles')) {
                return self::noSoapbox('ArticlesAbout');
            }

            return "query ArticlesAbout(\$id: ID!, \$first: Int) {\n  " . $open
                . 'articles { list(first: $first) { nodes { ' . self::articleFields($shape) . ' } } }'
                . $close . "\n}";
        }];
    }

    public static function submitOpEd(): string
    {
        return "mutation SubmitOpEd(\$publicationId: ID!, \$title: String!, \$body: String!, \$summary: String, \$byline: String) {\n"
            . '  submitOpEd(input: { publicationId: $publicationId, title: $title, body: $body, summary: $summary,'
            . " byline: \$byline }) {\n"
            . '    article { ' . self::ARTICLE_FIELDS . " status reviewNote submittedAt }\n  }\n}";
    }

    /**
     * Every document the SDK can send, built for an audience with every module, by operation name. CI checks them
     * against the API schema (`bin/graphql-documents`).
     *
     * @return array<string, string>
     */
    public static function all(): array
    {
        $everything = SchemaShape::everything();

        return [
            'Audience' => self::AUDIENCE,
            'Me' => self::ME,
            'RSVPEvent' => self::RSVP_EVENT,
            'CancelRSVP' => self::CANCEL_RSVP,
            'EventRSVP' => self::EVENT_RSVP,
            'DeleteAccount' => self::DELETE_ACCOUNT,
            'ReportContent' => self::REPORT_CONTENT,
            'BlockUser' => self::BLOCK_USER,
            'UnblockUser' => self::UNBLOCK_USER,
            'CalendarFeed' => self::calendarFeed(),
            'CreateCalendarFeed' => self::createCalendarFeed(),
            'SetCalendarFeedVenue' => self::setCalendarFeedVenue(),
            'DeleteCalendarFeed' => self::DELETE_CALENDAR_FEED,
            'ReportLocation' => self::reportLocation('venue { id name } locale { id name }'),
            'ChatRoom' => self::chatRoom('venue'),
            'LocaleChatRoom' => str_replace('subscription ChatRoom', 'subscription LocaleChatRoom', self::chatRoom('locale', true)),
            'BuyCoatCheck' => self::buyCoatCheck(),
            'Articles' => self::articles($everything),
            'ArticlesPage' => self::articlesPage($everything),
            'NationalArticles' => self::nationalArticles($everything),
            'Article' => self::article($everything),
            'Publications' => self::publications($everything),
            'Publication' => self::publication($everything),
            'MyOpEds' => self::myOpEds($everything),
            'ArticlesAboutVenue' => self::renamed(self::articlesAbout('venue')[1]($everything), 'ArticlesAboutVenue'),
            'ArticlesAboutEvent' => self::renamed(self::articlesAbout('event')[1]($everything), 'ArticlesAboutEvent'),
            'ArticlesAboutPerson' => self::renamed(self::articlesAbout('person')[1]($everything), 'ArticlesAboutPerson'),
            'ArticlesAboutLocale' => self::renamed(self::articlesAbout('locale')[1]($everything), 'ArticlesAboutLocale'),
            'SubmitOpEd' => self::submitOpEd(),
            'Tribes' => self::TRIBES,
            'IdentifyWithTribe' => self::IDENTIFY_WITH_TRIBE,
            'LeaveTribe' => self::LEAVE_TRIBE,
            'RegisterDevice' => self::REGISTER_DEVICE,
            'Node' => self::NODE,
            'SendMyChatMessage' => self::SEND_CHAT_MESSAGE,
            'RemoveMyChatMessage' => self::REMOVE_CHAT_MESSAGE,
            'Admissions' => self::admissions(),
            'BuyCover' => self::buyCover(),
            'PayCover' => self::payCover(),
            'ConfirmCover' => self::confirmCover(),
            'RefundAdmission' => self::refundAdmission(),
            'Venues' => self::venues($everything),
            'People' => self::people($everything),
            'Locales' => self::locales($everything),
            'ClosestLocale' => self::closestLocale($everything),
            'VenueCover' => self::venueCover($everything),
            'VenueOffers' => self::venueOffers($everything),
            'Events' => self::events($everything),
            'Event' => self::event($everything),
            'EventSeries' => self::eventSeries($everything),
            'VenueDetail' => self::venueDetail($everything),
        ];
    }

    /** `$document` with its operation renamed, so the schema check sees each variant under its own name. */
    private static function renamed(string $document, string $name): string
    {
        return (string) preg_replace('/^(query|mutation|subscription) [A-Za-z]+/', '$1 ' . $name, $document, 1);
    }

    private function __construct()
    {
    }
}
