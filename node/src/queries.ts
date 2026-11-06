import { SchemaShape } from "./schemaShape.js";
import { chatRoomArgument, type ChatRoom } from "./models.js";

/**
 * The GraphQL documents behind the client's typed helpers, the same ones the Swift and Kotlin SDKs send. Public so apps
 * can reuse the field lists in their own operations and read the same shapes.
 *
 * Field lists that include module fields take the audience's `SchemaShape`: the API leaves a module's fields out of
 * an audience that hasn't installed it, and asking for one fails the whole operation.
 */
export const PAGE_FIELDS = "id name photoUrl bannerUrl";
export const TAG_FIELDS = "id name color";
export const MONEY_FIELDS = "cents currency";
export const PROFILE_FIELDS = "id name avatarUrl";
export const COVER_CHARGE_FIELDS =
  `amount { ${MONEY_FIELDS} } total { ${MONEY_FIELDS} } fee { ${MONEY_FIELDS} } night from payable event { id name } ` +
  `coatCheck { amount { ${MONEY_FIELDS} } fee { ${MONEY_FIELDS} } total { ${MONEY_FIELDS} } night payable }`;
/** An `Admission`, with the pass secret the buyer makes the QR code from. */
export const ADMISSION_FIELDS =
  `id status kind night quantity tier claimCheckNumber amount { ${MONEY_FIELDS} } fee { ${MONEY_FIELDS} } ` +
  `total { ${MONEY_FIELDS} } isRefundable ` +
  `passSecret scanCount checkedInAt createdAt profile { ${PROFILE_FIELDS} } venue { id name photoUrl } event { id name }`;
/** An event's rsvp mixin for the signed-in user: how many are going, and their own answer. */
export const RSVP_FIELDS = "count mine mineSource";
export const EVENT_ATTENDEE_FIELDS = `profile { ${PROFILE_FIELDS} } friend source`;
export const ADMISSION_OFFER_FIELDS = `price { ${MONEY_FIELDS} } url seller { key name }`;
export const CHAT_MESSAGE_FIELDS = "id body message name userId avatarUrl photoUrl sentAt role kind title pinned";

/** The types whose fields the listing documents depend on. */
export const LISTING_TYPES = ["Locale", "ListingProfile", "Venue", "Location", "Person", "Event"] as const;
/** The types whose fields the event documents depend on. */
export const EVENT_TYPES = [...LISTING_TYPES, "EventSeries", "EventTickets"] as const;
/** The types `venueCover` and `venueOffers` depend on. */
export const VENUE_TICKET_TYPES = ["Venue", "VenueTickets"] as const;

const EVERYTHING = SchemaShape.EVERYTHING;

/** A locale, with its Google place ID (Listings and Google Places). */
export function localeFields(shape: SchemaShape = EVERYTHING): string {
  const places = shape.has("Locale", "profile") && shape.has("ListingProfile", "places") ? " profile { places { placeId } }" : "";
  return `id name label cityNames bannerUrl${places}`;
}

/** A venue in a list: its Facebook Page (Listings and Facebook) and its location's Google place ID. */
export function venueFields(shape: SchemaShape = EVERYTHING): string {
  const page =
    shape.has("Venue", "profile") && shape.has("ListingProfile", "facebook") ? `profile { facebook { page { ${PAGE_FIELDS} } } } ` : "";
  const place = shape.has("Location", "places") ? " places { placeId }" : "";
  return (
    `id name hidden order photoUrl bannerUrl ${page}locale { ${localeFields(shape)} } ` +
    `location { id point address${place} } tags { ${TAG_FIELDS} }`
  );
}

export const audience = `query Audience {
  id name subdomain theme { preset tagline light { name value } dark { name value } }
}`;

export function venues(shape: SchemaShape = EVERYTHING): string {
  return `query Venues {
  venues { list { nodes { ${venueFields(shape)} } } }
}`;
}

export function people(shape: SchemaShape = EVERYTHING): string {
  const page =
    shape.has("Person", "profile") && shape.has("ListingProfile", "facebook") ? `profile { facebook { page { ${PAGE_FIELDS} } } } ` : "";
  return `query People {
  people { list { nodes { id name order global likeRequired ${page}tags { ${TAG_FIELDS} } } } }
}`;
}

export function locales(shape: SchemaShape = EVERYTHING): string {
  return `query Locales {
  locales { ${localeFields(shape)} }
}`;
}

export const me = `query Me {
  me { self { id name firstName lastName emailAddress isAdmin presence } }
}`;

export function closestLocale(shape: SchemaShape = EVERYTHING): string {
  return `query ClosestLocale($near: CoordinatesInput!) {
  closestLocale(near: $near) { ${localeFields(shape)} }
}`;
}

/**
 * Records the user's position and says where that is: `venue` when they're in one, else `locale` and its
 * `nearbyVenues`, plus `audience` for its mixins. Select the fields the app needs and read the result yourself;
 * `$position` is a `coordinatesInput`.
 */
export function reportLocation(fields: string): string {
  return `mutation ReportLocation($position: CoordinatesInput!) {
  reportLocation(input: { position: $position }) { ${fields} }
}`;
}

export const rsvpEvent = `mutation RSVPEvent($eventId: ID!, $state: RSVPState!) {
  rsvpEvent(input: { eventId: $eventId, state: $state }) { event { id rsvp { ${RSVP_FIELDS} } } }
}`;

export const cancelRsvp = `mutation CancelRSVP($eventId: ID!) {
  cancelRsvp(input: { eventId: $eventId }) { event { id rsvp { ${RSVP_FIELDS} } } }
}`;

/** Who's going to an event: `RSVP_FIELDS`, the staff-only counts and the first `$first` attendees. */
export const eventRsvp = `query EventRSVP($id: ID!, $first: Int) {
  events {
    event(id: $id) {
      id
      rsvp {
        ${RSVP_FIELDS} counts { going interested tickets }
        attendees(first: $first) { nodes { ${EVENT_ATTENDEE_FIELDS} } }
      }
    }
  }
}`;

/** The tribes people can identify with here, and the signed-in user's own. */
export const tribes = `query Tribes {
  id tribes: tags(tribes: true) { ${TAG_FIELDS} tribe }
  me { self { id tribes { isPrivate tag { ${TAG_FIELDS} tribe } } } }
}`;

export const identifyWithTribe = `mutation IdentifyWithTribe($tagId: ID!, $isPrivate: Boolean) {
  identifyWithTribe(input: { tagId: $tagId, isPrivate: $isPrivate }) {
    tribes { isPrivate tag { ${TAG_FIELDS} tribe } }
  }
}`;

export const leaveTribe = `mutation LeaveTribe($tagId: ID!) {
  leaveTribe(input: { tagId: $tagId }) { tribes { isPrivate tag { ${TAG_FIELDS} tribe } } }
}`;

export const registerDevice = `mutation RegisterDevice($notificationToken: String!) {
  registerDevice(input: { notificationToken: $notificationToken }) { registered }
}`;

/** The signed-in user's cover passes, newest first. */
export const admissions = `query Admissions {
  me { cover { admissions { nodes { ${ADMISSION_FIELDS} } } } }
}`;

/** A venue's cover tonight and the signed-in user's pass for it; only the venue without the Ticketing and Cover modules. */
export function venueCover(shape: SchemaShape = EVERYTHING): string {
  const cover =
    shape.has("Venue", "tickets") && shape.has("VenueTickets", "cover")
      ? ` tickets { cover { charge { ${COVER_CHARGE_FIELDS} } viewerAdmission { ${ADMISSION_FIELDS} } viewerCoatCheck { ${ADMISSION_FIELDS} } } }`
      : "";
  return `query VenueCover($id: ID!) {
  venues { venue(id: $id) { id name${cover} } }
}`;
}

const PURCHASE_FIELDS = `admission { ${ADMISSION_FIELDS} }
    provider paymentIntentClientSecret publishableKey stripeAccountId squareApplicationId squareLocationId`;

export const buyCover = `mutation BuyCover($venueId: ID!) {
  buyCover(input: { venueId: $venueId }) {
    ${PURCHASE_FIELDS}
  }
}`;

export const buyCoatCheck = `mutation BuyCoatCheck($venueId: ID!, $quantity: Int) {
  buyCoatCheck(input: { venueId: $venueId, quantity: $quantity }) {
    ${PURCHASE_FIELDS}
  }
}`;

export const payCover = `mutation PayCover($admissionId: ID!, $sourceId: String!, $verificationToken: String) {
  payCover(input: { admissionId: $admissionId, sourceId: $sourceId, verificationToken: $verificationToken }) {
    admission { ${ADMISSION_FIELDS} }
  }
}`;

export const confirmCover = `mutation ConfirmCover($admissionId: ID!) {
  confirmCover(input: { admissionId: $admissionId }) { admission { ${ADMISSION_FIELDS} } }
}`;

export const refundAdmission = `mutation RefundAdmission($admissionId: ID!) {
  refundAdmission(input: { admissionId: $admissionId }) { admission { ${ADMISSION_FIELDS} } }
}`;

export const node = `query Node($id: ID!) {
  node(id: $id) { __typename id }
}`;

// Events

/** The Venues module's part of an event or series. */
export function eventVenueFields(shape: SchemaShape = EVERYTHING): string {
  const place = shape.has("Location", "places") ? " places { placeId }" : "";
  return `venue { name venue { id name photoUrl location { id point address${place} } } }`;
}

/** The Ticketing module's part of an event, with the Cover module's charge when the audience has it. */
export function eventTicketsFields(shape: SchemaShape = EVERYTHING): string {
  const cover = shape.has("EventTickets", "cover") ? ` cover { charge { ${COVER_CHARGE_FIELDS} } }` : "";
  return `tickets { url offers { nodes { ${ADMISSION_OFFER_FIELDS} } }${cover} }`;
}

/** An event: its own fields, then those of the Venues, RSVP, People and Ticketing modules the audience has. */
export function eventFields(shape: SchemaShape = EVERYTHING): string {
  let fields =
    "id name description startAt endAt isFeatured isCanceled bannerUrl sourceUrl " +
    `locale { ${localeFields(shape)} } tags { ${TAG_FIELDS} }`;
  if (shape.has("Event", "venue")) fields += ` ${eventVenueFields(shape)}`;
  if (shape.has("Event", "rsvp")) fields += " rsvp { mine count }";
  if (shape.has("Event", "people")) {
    fields += " people { hosts { nodes { id name avatarUrl } } lineup { nodes { id name avatarUrl } } }";
  }
  if (shape.has("Event", "tickets")) fields += ` ${eventTicketsFields(shape)}`;
  return fields;
}

export function eventSeriesFields(shape: SchemaShape = EVERYTHING): string {
  const venue = shape.has("EventSeries", "venue") ? ` ${eventVenueFields(shape)}` : "";
  return (
    "id name description recurrenceText startsOn startTime timeZone durationMinutes bannerUrl " +
    `locale { ${localeFields(shape)} } tags { ${TAG_FIELDS} }${venue}`
  );
}

export function events(shape: SchemaShape = EVERYTHING): string {
  return `query Events($window: EventWindow, $localeId: ID, $venueId: ID, $first: Int) {
  events {
    list(window: $window, localeId: $localeId, venueId: $venueId, first: $first) {
      nodes { ${eventFields(shape)} }
    }
  }
}`;
}

export function event(shape: SchemaShape = EVERYTHING): string {
  return `query Event($id: ID!) {
  events { event(id: $id) { ${eventFields(shape)} } }
}`;
}

export function eventSeries(shape: SchemaShape = EVERYTHING): string {
  return `query EventSeries($localeId: ID, $venueId: ID, $first: Int) {
  events {
    series(localeId: $localeId, venueId: $venueId, first: $first) { nodes { ${eventSeriesFields(shape)} } }
  }
}`;
}

/** Every way into a venue on a night, or just the venue where the audience doesn't have the Ticketing module. */
export function venueOffers(shape: SchemaShape = EVERYTHING): string {
  // A variable the document doesn't use is an error, so night goes with the field.
  const hasTickets = shape.has("Venue", "tickets");
  const offers = hasTickets ? ` tickets { offers(night: $night) { nodes { ${ADMISSION_OFFER_FIELDS} } } }` : "";
  const night = hasTickets ? ", $night: ISO8601Date" : "";
  return `query VenueOffers($id: ID!${night}) {
  venues { venue(id: $id) { id${offers} } }
}`;
}

// Venue page and chat

export function venueDetail(shape: SchemaShape = EVERYTHING): string {
  // A variable the document doesn't use is an error, so recentMessages goes with the chat field.
  const recentMessages = shape.has("Venue", "chat") ? ", $recentMessages: Int" : "";
  let fields = `${venueFields(shape)} description`;
  if (shape.has("Venue", "profile")) {
    fields += " profile { address phone website socialLinks { nodes { id handle provider url } } }";
  }
  if (shape.has("Venue", "chat")) {
    fields += ` chat { open recentMessages(limit: $recentMessages) { nodes { ${CHAT_MESSAGE_FIELDS} } } }`;
  }
  if (shape.has("Venue", "events")) fields += ` events { upcoming(first: 20) { nodes { ${eventFields(shape)} } } }`;
  return `query VenueDetail($id: ID!${recentMessages}) {
  venues { venue(id: $id) { ${fields} } }
}`;
}

export const sendChatMessage = `mutation SendMyChatMessage($input: ChatMessageSendOwnInput!) {
  sendMyChatMessage(input: $input) { message { ${CHAT_MESSAGE_FIELDS} } }
}`;

export const removeChatMessage = `mutation RemoveMyChatMessage($messageId: ID!) {
  removeMyChatMessage(input: { messageId: $messageId }) { deletedId }
}`;

/** A chat room's subscription, aliased to `room` whichever field it is, for an app with its own Action Cable client. */
export function chatRoom(room: ChatRoom, watch = false): string {
  const field = room.kind === "venue" ? "venueChat" : "localeChat";
  return `subscription ChatRoom($id: ID!) {
  room: ${field}(${chatRoomArgument(room)}: $id${watch ? ", watch: true" : ""}) {
    __typename
    ... on ChatJoined {
      outOfRange
      roster { people { userId name avatarUrl friend } }
      history { message { ...Line } }
      pinnedMessage { message { ...Line } }
    }
    ... on ChatMessagePosted { message { ...Line } }
    ... on ChatMessageUpdated { message { ...Line } }
    ... on ChatMessageRemoved { messageId }
    ... on ChatPinChanged { messageId pinned announcement { ...Line } }
    ... on ChatRoomCleared { clearedAt expired }
    ... on ChatPresenceChanged { userId name avatarUrl presence }
    ... on ChatRangeChanged { outOfRange }
    ... on ChatLeft { reason }
  }
}
fragment Line on ChatMessage { ${CHAT_MESSAGE_FIELDS} }`;
}
