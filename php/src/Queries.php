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
    public const COVER_CHARGE_FIELDS = 'amount { cents currency } fee { cents currency } total { cents currency }'
        . ' night from payable event { id name }';
    /** An admission: the pass secret the buyer makes the QR code from, and the buyer's profile for the door. */
    public const ADMISSION_FIELDS = 'id status night amount { cents currency } total { cents currency } isRefundable'
        . ' passSecret scanCount checkedInAt profile { id name avatarUrl } venue { id name photoUrl } event { id name }';
    public const ADMISSION_OFFER_FIELDS = 'price { cents currency } url seller { key name }';
    public const CHAT_MESSAGE_FIELDS = 'id body message name userId avatarUrl photoUrl sentAt role kind title pinned';

    /** The types whose fields the listing documents depend on. */
    public const LISTING_TYPES = ['Locale', 'ListingProfile', 'Venue', 'Location', 'Person', 'Event'];
    /** The types the event documents depend on. */
    public const EVENT_TYPES = [...self::LISTING_TYPES, 'EventSeries', 'EventTickets'];
    /** The types `venueCover` and `venueOffers` depend on. */
    public const VENUE_TICKET_TYPES = ['Venue', 'VenueTickets'];
    public const VENUE_DETAIL_TYPES = self::EVENT_TYPES;

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
          rsvpEvent(input: { eventId: $eventId, state: $state }) { event { id rsvp { mine } } }
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

    public static function admissions(): string
    {
        return "query Admissions {\n  me { cover { admissions { nodes { " . self::ADMISSION_FIELDS . " } } } }\n}";
    }

    public static function buyCover(): string
    {
        return "mutation BuyCover(\$venueId: ID!) {\n  buyCover(input: { venueId: \$venueId }) {\n"
            . '    admission { ' . self::ADMISSION_FIELDS . " }\n"
            . "    provider paymentIntentClientSecret publishableKey stripeAccountId squareApplicationId squareLocationId\n"
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
                . self::ADMISSION_FIELDS . ' } } }'
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
            $fields .= ' people { hosts { nodes { id name avatarUrl } } lineup { nodes { id name avatarUrl } } }';
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

    private function __construct()
    {
    }
}
