import { coordinateFromWkt, type Coordinate } from "./coordinates.js";

/** The audience a client is scoped to. */
export interface Audience {
  id: string;
  name: string;
  subdomain: string;
  theme?: AudienceTheme | null;
}

/** An audience's look, as GraphQL returns it: a preset, a tagline and color token overrides. */
export interface AudienceTheme {
  preset: string;
  tagline?: string | null;
  light?: ThemeToken[];
  dark?: ThemeToken[];
}

/** One design-system color token, e.g. `accent` = `#b8236f`. */
export interface ThemeToken {
  name: string;
  value: string;
}

/** The Facebook page behind a venue or person: its name and pictures. */
export interface Page {
  id: string;
  name: string;
  /** Profile picture, as the API sends it. Use `client.url()` to resolve relative paths. */
  photoUrl?: string | null;
  bannerUrl?: string | null;
}

/** A listing's or location's Google Maps side: GraphQL's `IPlacesProfile`. */
export interface PlacesProfile {
  placeId?: string | null;
}

/** A listing's Facebook side: GraphQL's `IFacebookProfile`. */
export interface FacebookProfile {
  page?: Page | null;
}

/**
 * A venue's, person's or locale's public profile: GraphQL's `profile` mixin (`IListingProfile`), with the facebook and
 * places modules' parts. Only what the SDK's queries select; a part the query left out is absent.
 */
export interface ListingProfile {
  facebook?: FacebookProfile | null;
  places?: PlacesProfile | null;
}

/** A city or region the audience is active in. */
export interface AudienceLocale {
  id: string;
  name?: string | null;
  label?: string | null;
  cityNames?: string[] | null;
  bannerUrl?: string | null;
  /** Its listing profile: `profile { places { placeId } }`. */
  profile?: ListingProfile | null;
}

/** A locale's Google place ID (a city or region), when an admin has set one. */
export function localeGooglePlaceId(locale: AudienceLocale): string | null {
  return locale.profile?.places?.placeId ?? null;
}

/** A place: a Google place with a point. */
export interface Location {
  id: string;
  /** The point as the API serializes it (WKT, e.g. `POINT (-122.42 37.77)`). */
  point?: string | null;
  address?: string | null;
  /** The places module's part: `places { placeId }`. */
  places?: PlacesProfile | null;
}

/** A location's `point` parsed into latitude and longitude, when it is a WKT point. */
export function locationCoordinate(location: Location | null | undefined): Coordinate | null {
  return location?.point ? coordinateFromWkt(location.point) : null;
}

/** One of the audience's own labels, like "Drag" or "Resident DJ", on its people, events and venues. */
export interface Tag {
  id: string;
  name: string;
  /** A `#rrggbb` color for its chip, or null for the theme's accent. */
  color?: string | null;
  /** Whether people can identify with it (see `TribeIdentification`). */
  tribe?: boolean;
}

/** A venue in the audience. */
export interface Venue {
  id: string;
  /** The venue's own name; `venueName()` falls back to its Facebook Page's. */
  name?: string | null;
  hidden: boolean;
  order: number;
  photoUrl?: string | null;
  bannerUrl?: string | null;
  /** Its listing profile: `profile { facebook { page } }`. */
  profile?: ListingProfile | null;
  locale: AudienceLocale;
  location?: Location | null;
  /** The audience's tags on it, by name. */
  tags?: Tag[];
}

/** A venue's or person's Facebook Page; listings added without one have none. */
export function listingPage(listing: { profile?: ListingProfile | null }): Page | null {
  return listing.profile?.facebook?.page ?? null;
}

/** A venue's or person's name as the audience shows it, falling back to their Facebook Page's. */
export function listingName(listing: { name?: string | null; profile?: ListingProfile | null }): string {
  return listing.name ?? listingPage(listing)?.name ?? "";
}

/** A person (performer, promoter, DJ...) the audience follows. */
export interface Person {
  id: string;
  name?: string | null;
  order: number;
  global: boolean;
  likeRequired: boolean;
  profile?: ListingProfile | null;
  tags?: Tag[];
}

/**
 * Someone identifying with one of the audience's tribes. A private one may be sensitive (HIV status, say): the API only
 * ever shows it to them and to people in the same tribe, and apps should keep it discreet.
 */
export interface TribeIdentification {
  tag: Tag;
  isPrivate: boolean;
}

/** The tribes people can identify with in an audience, and which of them the signed-in user has. */
export interface Tribes {
  available: Tag[];
  mine: TribeIdentification[];
}

/**
 * Whether someone can be reached right now: GraphQL's `Presence`. The API shows the real value only to the person,
 * their friends and admins; everyone else gets `OFFLINE`.
 */
export type Presence = "ONLINE" | "PUSH" | "OFFLINE";

/** The signed-in user's own profile (`me { self }`, a SelfUser): what only they see as well as their public fields. */
export interface SelfUser {
  id: string;
  name?: string | null;
  firstName?: string | null;
  lastName?: string | null;
  emailAddress?: string | null;
  isAdmin?: boolean | null;
  presence?: Presence | null;
}

/** Any record, as `node(id:)` returns it: its UUID and its GraphQL type. */
export interface Node {
  id: string;
  /** The GraphQL type name, e.g. `Venue`. */
  __typename?: string;
}

/** Whether the signed-in user is going to an event. The GraphQL enum's values. */
export type RSVPState = "ATTENDING" | "MAYBE" | "DECLINED" | "UNSURE";

/** Why someone counts as going to an event: they RSVPed, or they hold a ticket (a ticket is an RSVP). */
export type RSVPSource = "RSVP" | "TICKET";

/** How many are going (RSVPed attending or holding a ticket), interested, and holding tickets. Staff only. */
export interface RSVPCounts {
  going: number;
  interested: number;
  tickets?: number;
}

/**
 * Who someone is, as the signed-in user may see them (`Profile`): their `id`, their `name` (in full for themself,
 * their friends and staff; "Aurora B." for anyone else) and their picture.
 */
export interface Profile {
  id: string;
  name: string;
  avatarUrl?: string | null;
}

/** Someone going to an event: who they are, and how they count as going. */
export interface EventAttendee {
  profile: Profile;
  friend?: boolean;
  source?: RSVPSource;
}

/**
 * Who's going to an event, from its rsvp module: everyone who RSVPed attending and, where the audience sells tickets,
 * everyone holding one. `mine` is the signed-in user's answer (`ATTENDING` when they hold a ticket, `UNSURE` signed
 * out). `counts` is there only for the event's staff. `attendees` is empty signed out.
 */
export interface EventRSVP {
  count: number;
  mine: RSVPState;
  mineSource?: RSVPSource | null;
  counts?: RSVPCounts | null;
  attendees: EventAttendee[];
}

/**
 * An amount of money as the API gives it: whole `cents` of a `currency` (its lower-case ISO 4217 code, e.g. `usd`).
 * $10.00 is `{ cents: 1000, currency: "usd" }`.
 */
export interface Money {
  cents: number;
  currency: string;
}

/** The event an `Admission` or `CoverCharge` is for. */
export interface CoverEvent {
  id: string;
  name?: string | null;
}

/** The venue an `Admission` is for. */
export interface CoverVenue {
  id: string;
  name?: string | null;
  photoUrl?: string | null;
}

/** What checking a coat costs at a venue on a night. Show `total`, the all-in price per coat. */
export interface CoatCheck {
  amount: Money;
  total: Money;
  fee?: Money;
  /** The night it is for, as an ISO 8601 date. */
  night: string;
  payable?: boolean;
}

/**
 * What it costs to get into a venue on a night. Show `total`, the all-in price; when `payable` is true it can be paid
 * in the app with `buyCover`, otherwise it's paid at the door.
 */
export interface CoverCharge {
  /** The cover the venue receives. */
  amount: Money;
  /** What the buyer pays, all in. */
  total: Money;
  /** The audience's fee in it. */
  fee?: Money;
  /** The night it is for, as an ISO 8601 date (`2026-10-09`). A night runs 6am to 6am. */
  night: string;
  /** When the cover starts, a TimeOfDay (`HH:MM`, local), e.g. `21:00`. */
  from?: string | null;
  payable?: boolean;
  /** The event that night, when it sets the night's cover. */
  event?: CoverEvent | null;
  /** The venue's coat check that night, when it has one: pay it with `buyCoatCheck`. */
  coatCheck?: CoatCheck | null;
}

/** What an `Admission` gets you: in the door, or a coat checked. */
export type AdmissionKind = "COVER" | "COAT_CHECK";

/** Where a cover payment stands. The GraphQL enum's values. */
export type AdmissionStatus = "PENDING" | "PAID" | "FAILED" | "CANCELED" | "REFUNDED" | "DISPUTED";

/**
 * Someone's cover for one night at a venue, and their pass. Make the pass's QR code with `coverPassCode` from
 * `passSecret`, which only the buyer gets.
 */
export interface Admission {
  id: string;
  status: AdmissionStatus;
  kind?: AdmissionKind;
  /** The night it is for, as an ISO 8601 date. */
  night: string;
  /** How many people (cover) or coats (coat check) it's for. */
  quantity?: number;
  /** The cover tier bought, when the venue has tiers. */
  tier?: string | null;
  /** A coat check pass's ticket number, once the venue has given one out. */
  claimCheckNumber?: string | null;
  amount?: Money;
  fee?: Money;
  total?: Money;
  /** Whether the buyer can refund it themselves: paid, not scanned in, and the night isn't over. */
  isRefundable?: boolean;
  /** The Base64 key the pass's QR code is made with. The buyer only; null for everyone else. */
  passSecret?: string | null;
  /** How many times the door has scanned it. */
  scanCount?: number;
  /** When the door first scanned it, as ISO 8601. */
  checkedInAt?: string | null;
  createdAt?: string | null;
  /** The buyer: their name for the pass and the door, their picture so the door can match faces. */
  profile?: Profile | null;
  venue?: CoverVenue | null;
  /** The event that night, if it set the cover. */
  event?: CoverEvent | null;
}

/** Whether a pass is paid: the status says so. */
export function isAdmissionPaid(admission: Admission): boolean {
  return admission.status === "PAID";
}

/** What `buyCover` returns: the pass, and what Stripe's payment sheet or Square's SDK needs. */
export interface CoverPurchase {
  /** The pass, pending until the payment succeeds. */
  admission: Admission;
  /** `STRIPE` or `SQUARE`: Stripe venues pay with Stripe's payment sheet, Square venues with Square's SDK. */
  provider?: "STRIPE" | "SQUARE" | string;
  /** Stripe: for the payment sheet; null once it's paid. */
  paymentIntentClientSecret?: string | null;
  /** Stripe: the audience's publishable key. */
  publishableKey?: string | null;
  /** Stripe: the venue's account; the payment is a direct charge on it. */
  stripeAccountId?: string | null;
  /** Square: the audience's application ID. */
  squareApplicationId?: string | null;
  /** Square: the venue's location that gets paid. */
  squareLocationId?: string | null;
}

/** Whether a purchase pays through Square rather than Stripe. */
export function isSquarePurchase(purchase: CoverPurchase): boolean {
  return purchase.provider === "SQUARE";
}

/** Whether there's nothing left to pay on a purchase. */
export function isPurchasePaid(purchase: CoverPurchase): boolean {
  return isAdmissionPaid(purchase.admission) || (!isSquarePurchase(purchase) && purchase.paymentIntentClientSecret == null);
}

/** The part of a venue's `tickets { cover }` mixin a fan reads. */
export interface ViewerCover {
  /** Tonight's cover, or null when there is none. */
  charge?: CoverCharge | null;
  /** The signed-in user's cover for tonight, paid or being paid. */
  viewerAdmission?: Admission | null;
  /** The signed-in user's coat check for tonight, paid or being paid. */
  viewerCoatCheck?: Admission | null;
}

/** A venue's cover tonight and the signed-in user's pass for it. */
export interface VenueCover {
  id: string;
  name?: string | null;
  /** Its tickets mixin, carrying the cover mixin inside it. Absent without the Ticketing and Cover modules. */
  tickets?: { cover?: ViewerCover | null } | null;
}

/** A connection read as `nodes { … }`. */
export interface Connection<T> {
  nodes?: (T | null)[] | null;
}

/** A connection's nodes, without the nulls the API sends for records the viewer can't see. */
export function connectionItems<T>(connection: Connection<T> | null | undefined): T[] {
  return (connection?.nodes ?? []).filter((node): node is T => node !== null && node !== undefined);
}

// Events

/** Which events `events()` lists: the API's `EventWindow`. */
export type EventWindow = "UPCOMING" | "PAST";

/** A venue an event or series is at: the `venue { venue }` of the API's venues module. */
export interface EventVenue {
  id: string;
  name?: string | null;
  photoUrl?: string | null;
  /** Where it is; `locationCoordinate` parses the API's WKT point. */
  location?: Location | null;
}

/** The API's `venue` mixin on an event or series: a display name ("To be announced" when there is none) and the venue. */
export interface EventVenueMixin {
  name?: string | null;
  venue?: EventVenue | null;
}

/** Someone on an event's bill: a host or a performer on its lineup. */
export interface EventPerson {
  id: string;
  name?: string | null;
  avatarUrl?: string | null;
}

/** The signed-in user's RSVP to an event and how many are going, as a list shows it: `rsvp { mine count }`. */
export interface EventRSVPSummary {
  mine?: RSVPState;
  count?: number;
}

export interface EventPeople {
  hosts?: Connection<EventPerson> | null;
  lineup?: Connection<EventPerson> | null;
}

/** Who sells an admission (the API's `IProvider`): a ticketing partner, or AudienceKit itself. */
export interface Seller {
  key: string;
  name: string;
}

/** A way into an event or a venue night (the API's `IAdmissionOffer`): tickets on a partner, or the cover. */
export interface AdmissionOffer {
  /** What it costs the buyer, all in (the lowest price for tickets); null when the seller doesn't say. */
  price?: Money | null;
  /** Where to buy it on the web; null when it's bought in the app (the cover) or at the door. */
  url?: string | null;
  seller: Seller;
}

/** The Ticketing module's part of an event: where to buy tickets, every offer and (with Cover) the night's cover. */
export interface EventTickets {
  url?: string | null;
  offers?: Connection<AdmissionOffer> | null;
  cover?: { charge?: CoverCharge | null } | null;
}

/**
 * An event in the audience: a night, a meetup or a conference. The parts modules add are absent when the audience
 * hasn't installed that module: `venue` (Venues), `rsvp` (RSVP), `people` (People) and `tickets` (Ticketing). The SDK
 * asks for them and, if the audience's schema doesn't have one, asks again without.
 */
export interface Event {
  id: string;
  name?: string | null;
  description?: string | null;
  /** ISO 8601; null when not scheduled yet. */
  startAt?: string | null;
  endAt?: string | null;
  isFeatured?: boolean;
  isCanceled?: boolean;
  bannerUrl?: string | null;
  /** Where it was listed from (its calendar or website), if it was imported. */
  sourceUrl?: string | null;
  locale?: AudienceLocale | null;
  tags?: Tag[];
  venue?: EventVenueMixin | null;
  rsvp?: EventRSVPSummary | null;
  people?: EventPeople | null;
  tickets?: EventTickets | null;
}

/** Where an event is; null while the venue is still to be announced. */
export function eventVenue(event: Event | EventSeries): EventVenue | null {
  return event.venue?.venue ?? null;
}

/** An event's hosts, or null without the People module. */
export function eventHosts(event: Event): EventPerson[] | null {
  return event.people ? connectionItems(event.people.hosts) : null;
}

/** An event's lineup, or null without the People module. */
export function eventLineup(event: Event): EventPerson[] | null {
  return event.people ? connectionItems(event.people.lineup) : null;
}

/** Every way into an event on sale, whichever module sells it; null without the Ticketing module. */
export function eventTicketOffers(event: Event): AdmissionOffer[] | null {
  return event.tickets ? connectionItems(event.tickets.offers) : null;
}

/** The cover at an event's venue that night: null when there's none, when it sells tickets, or without the Cover module. */
export function eventCoverCharge(event: Event): CoverCharge | null {
  return event.tickets?.cover?.charge ?? null;
}

/** A recurring event: a weekly meetup or a monthly night. */
export interface EventSeries {
  id: string;
  name: string;
  description?: string | null;
  /** How it repeats, in words, e.g. "Every Tuesday". */
  recurrenceText?: string | null;
  /** The first night, `yyyy-MM-dd`. */
  startsOn: string;
  /** When each night starts, `HH:mm`, in `timeZone`. */
  startTime: string;
  timeZone: string;
  durationMinutes?: number | null;
  bannerUrl?: string | null;
  locale?: AudienceLocale | null;
  tags?: Tag[];
  venue?: EventVenueMixin | null;
}

// Chat

/** A chat room: a venue's, or a locale's (out in the city, away from its venues). */
export type ChatRoom = { kind: "venue"; id: string } | { kind: "locale"; id: string };

/** The argument naming a room on `sendMyChatMessage`'s input and its subscription. */
export function chatRoomArgument(room: ChatRoom): "venueId" | "localeId" {
  return room.kind === "venue" ? "venueId" : "localeId";
}

/** One message in a chat room: the API's `ChatMessage`. */
export interface ChatMessage {
  id: string;
  /** What it says, rendered for display. */
  body?: string;
  /** The text as sent. */
  message?: string;
  /** Who sent it, as the room shows them (non-friends as "First L."), or the venue's name. */
  name?: string | null;
  userId?: string | null;
  avatarUrl?: string | null;
  photoUrl?: string | null;
  /** ISO 8601. */
  sentAt?: string | null;
  /** The API's `ChatRole` (`HOST`, `STAFF`, `VENUE`); null for a member. */
  role?: string | null;
  /** The API's `ChatKind`: `TEXT`, `ANNOUNCEMENT`, `PHOTO`, `EVENT`, `SPECIAL`, `PROMPT`, `REQUEST`. */
  kind?: string;
  title?: string | null;
  pinned?: boolean;
}

/** One of a venue's or person's social media profiles: the API's `SocialLink`. */
export interface SocialLink {
  id: string;
  handle: string;
  provider: string;
  url?: string | null;
}

/** A venue's page: the venue and what the modules its audience has add to it; a module it lacks leaves its part null. */
export interface VenueDetail {
  venue: Venue;
  description: string | null;
  address: string | null;
  phone: string | null;
  website: string | null;
  socialLinks: SocialLink[] | null;
  chatOpen: boolean | null;
  recentMessages: ChatMessage[] | null;
  upcomingEvents: Event[] | null;
}

// Session

/**
 * A session the API issued, as `POST /v1/token` (every variant) and `POST /v1/token/refresh` return it. It says
 * everything the client needs, so nothing decodes the JWT. Treat the token like a password and never log it.
 */
export interface Credential {
  /** The session JWT, sent as `Authorization: Bearer <token>`. */
  token: string;
  /** The signed-in user's ID. */
  userId: string;
  /** The audience the session is bound to; null for a platform-console session. */
  audienceId?: string | null;
  /** The user's role in the audience: `member`, `listing`, `admin` or `venue_device`. */
  role: string;
  /** The GraphQL endpoint the token was issued for, as a full URL. */
  endpoint?: string | null;
  /** The venue device this session runs on, for venue-device sessions. */
  venueDeviceId?: string | null;
  /** When the session expires, ISO 8601; null when it only ends by signing out (the usual case). */
  expiresAt?: string | null;
}

/** What `GET /v1/branding?host=…` returns: who the audience is, its look, and the Facebook app its sign-in uses. */
export interface Branding {
  audience: { id: string; name: string; subdomain: string };
  facebook_app_id?: string | null;
  /** The Facebook Login for Business configuration to open the login dialog with, as `config_id`. */
  facebook_login_config_id?: string | null;
  theme?: BrandingTheme;
}

/** An audience's theme as branding sends it: token overrides keyed by token name. */
export interface BrandingTheme {
  /** Design system preset, e.g. `default` or `hot_mess`. */
  preset?: string;
  tagline?: string | null;
  /** Light-mode overrides, e.g. `{ accent: "#9c1c62" }`. */
  light?: Record<string, string>;
  dark?: Record<string, string>;
}
