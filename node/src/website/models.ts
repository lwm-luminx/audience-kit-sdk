// The shapes the website documents (`Website.Queries`) select, field for field: what a consumer website (hotmess.social)
// shows of a venue, event, person or post, where someone is (`reportLocation`), the poster builder's listings, safety
// alerts and privacy choices. Fields are nullable wherever the schema leaves them nullable, and optional only where a
// document may not select them. Moved here from hotmess.social's src/sdk/types.ts.

/** An absolute image URL. Null, never "", when there is no image (scalar PhotoURL). */
export type PhotoURL = string;

/** The signed-in user's answer to an event (enum RSVPState). */
export type RSVPState = "ATTENDING" | "MAYBE" | "DECLINED" | "UNSURE";

/** A Relay connection, as the documents select it: its nodes only. */
export interface Connection<T> {
  nodes: (T | null)[] | null;
}

/** The parts of a venue's or person's listing profile (IListingProfile) the site reads. */
export interface ListingProfile {
  address?: string | null;
  phone?: string | null;
  website?: string | null;
  /** Its Facebook Page's ID (a string: Page IDs overflow Int) and canonical Page, profile or public group URL. */
  facebook?: { facebookId: string | null; link?: string | null };
  socialLinks?: Connection<SocialLink>;
}

export interface VenueReference {
  id: string;
  name: string | null;
  /** Its own photo of the place. */
  photoUrl?: PhotoURL | null;
  /** Its first banner image, else its own photo, else its Facebook Page's cover photo. */
  bannerUrl?: PhotoURL | null;
  profile?: ListingProfile;
}

export interface Venue extends VenueReference {
  description?: string | null;
  /** Metres from where the request was made, on Now. */
  distance?: number | null;
  friends?: { list: Connection<Friend> };
  events?: { upcoming: Connection<Event> };
  /** How it takes food and drink orders: its own ordering page. A facet: null unless it has one. */
  ordering?: { url: string | null } | null;
}

export interface PersonReference {
  id: string;
  name: string | null;
  avatarUrl?: PhotoURL | null;
  profile?: ListingProfile;
}

export interface SocialLink {
  id: string;
  provider: string;
  handle: string;
  url: string | null;
}

export interface Track {
  id: string;
  title: string | null;
  provider?: string | null;
  providerUrl?: string | null;
  streamUrl?: string | null;
  artworkUrl?: string | null;
  releasedAt?: string | null;
}

export interface Person extends PersonReference {
  bannerUrl?: PhotoURL | null;
  music?: { links: Connection<SocialLink>; tracks: Connection<Track> };
  events?: { upcoming: Connection<Event> };
}

export interface Event {
  id: string;
  name: string | null;
  startAt: string | null;
  endAt: string | null;
  facebookId: string | null;
  bannerUrl: PhotoURL | null;
  rsvp?: { mine: RSVPState };
  /** Its venue mixin: the venue's name (or "To be announced") and the venue itself while it has one. */
  venue: { name: string; venue: Venue | null };
  /** Its people mixin: who is hosting it, and its whole lineup (hosts included). */
  people?: { hosts?: Connection<PersonReference>; lineup: Connection<PersonReference> };
}

export interface Friend {
  id: string;
  name: string | null;
  avatarUrl: PhotoURL | null;
  facebookId?: string | null;
}

export interface FriendVenue {
  venue: { id: string };
  friendCount: number;
}

export interface Locale {
  id: string;
  name: string | null;
  label?: string | null;
  bannerUrl?: PhotoURL | null;
  events?: { upcoming: Connection<Event> };
  friends?: { list: Connection<Friend>; venues: Connection<FriendVenue> };
}

/** What reportLocation answers (LocationReportPayload): where you are, and what's around it. */
export interface Now {
  /** The venue you're at, when you're at one. */
  venue: Venue | null;
  /** The locale you're in, or the closest one. */
  locale: Locale | null;
  /** The locale's venues, nearest first, when you're not at one. */
  nearbyVenues: Venue[] | null;
}

export type SafetyAlertState = "OPEN" | "ACKNOWLEDGED" | "CLOSED" | "CANCELLED";
export type SafetyPlace = "BAR" | "DANCE_FLOOR" | "RESTROOMS" | "PATIO" | "STAGE" | "ENTRANCE" | "UNSURE";
export type SafetyConcern = "BOTHERING" | "FOLLOWING" | "INTOXICATED" | "UNWELL" | "OTHER";

export interface SafetyAlertMessage { id: string; body: string; fromStaff: boolean; senderName: string; createdAt: string }

export interface SafetyAlert {
  id: string;
  state: SafetyAlertState;
  place: SafetyPlace | null;
  concerns: SafetyConcern[];
  description: string | null;
  summary: string;
  seen: boolean;
  acknowledgedByName: string | null;
  acknowledgedAt: string | null;
  escalatedAt: string | null;
  closedAt: string | null;
  supportSharedAt: string | null;
  supportNote: string | null;
  createdAt: string;
  venue: { id: string; name: string | null };
  messages: SafetyAlertMessage[];
}

export interface SafetyDraft { place: SafetyPlace | null; concerns: SafetyConcern[]; description: string }

export interface SupportLine {
  id: string; name: string; description: string | null; phone: string | null;
  textNumber: string | null; textBody: string | null; url: string | null;
}

/**
 * "Get a ride": a ride app (Uber, Lyft) as a plain link. `url` opens the app, or its site when it isn't installed;
 * `pickupUrl` does the same with the pickup set once {latitude}, {longitude} and {name} are filled in.
 */
export interface SupportRide { id: string; name: string; url: string; pickupUrl: string | null }

export interface SupportResources {
  region: string; name: string; emergency: string; checkedAt: string | null; lines: SupportLine[];
}

/** A place someone is in (`reportLocation`'s locale and locales), innermost first. */
export interface Place {
  id: string;
  label: string | null;
}

/** A post as its shared link shows it to someone signed in: comments stay in the app. */
export interface Post {
  id: string;
  body: string | null;
  posterName: string | null;
  posterAvatarUrl: string | null;
  actingPersonName: string | null;
  createdAt: string | null;
  edited: boolean | null;
  photos: { url: string | null; altText: string | null }[] | null;
  event: { id: string; name: string | null; startAt: string | null } | null;
  person: { id: string } | null;
  venue: { id: string } | null;
}

/** A venue as the poster builder finds it. */
export interface PosterVenue {
  id: string;
  name: string | null;
  locale: { name: string | null } | null;
  profile: { address: string | null } | null;
}

/** A recurring series as a poster shows it. */
export interface PosterSeries {
  id: string;
  name: string;
  /** Its rule in words, e.g. "Every week on Thursday". */
  recurrenceText: string | null;
  /** HH:MM, local to timeZone; "" for no time. */
  startTime: string;
  timeZone: string;
}

/** An event as a poster shows it. */
export interface PosterEvent {
  id: string;
  name: string | null;
  startAt: string | null;
  endAt: string | null;
  venue: { name: string | null; venue: { id: string; name: string | null; locale: { name: string | null } | null } | null } | null;
  /** The series it's one date of; null for a one-off. */
  eventSeries: PosterSeries | null;
}

/** What a venue charges at the door, for its cover poster. */
export interface PosterCover {
  cents: number | null;
  payable: boolean;
}

/** Whether someone can send a safety alert from a venue, and whether its staff are on shift. */
export interface VenueSafety {
  id: string;
  /** Its location as WKT (`POINT(lng lat)`), for a ride's pickup. */
  point: string | null;
  canSendSafetyAlert: boolean;
  safetyStaffOnShift: boolean;
}

/** The ways an audience lets people sign in, and what to say before each one that has a warning. */
export interface SignInMethods {
  methods: string[];
  warnings: Record<string, string>;
}

/** The privacy choices an audience offers (`privacyOffer`). */
export type PrivacyChoiceKey = "SALE_SHARE_OPT_OUT" | "AD_MEASUREMENT" | "PERSONALIZED_ADS" | "PRIVACY_PASS";

export interface PrivacyOffer {
  choices: PrivacyChoiceKey[];
  passCents: number | null;
  passDays: number;
}

/** Someone's privacy choices (`me.privacy`). */
export interface PrivacyChoices {
  saleShareOptedOut: boolean;
  saleShareOptOutSource: "CHOICE" | "GLOBAL_PRIVACY_CONTROL" | null;
  adMeasurement: boolean;
  countedInAdMeasurement: boolean;
  personalizedAds: boolean;
  mayShare: boolean;
  privacyPassUntil: string | null;
}

/** The privacy choices page: what the audience offers, and what someone chose (null when signed out). */
export interface Privacy {
  privacyOffer: PrivacyOffer;
  me: { privacy: PrivacyChoices } | null;
}

/** A privacy pass's checkout. */
export interface PrivacyPassCheckout {
  checkoutUrl: string;
  passId: string;
}

/** The API's answer for a share link (`GET /v1/share`): its HTTP status and, on 200, its card. */
export interface ShareLinkAnswer<T = Record<string, unknown>> {
  /** 200, 404 for nothing to share, 410 for an expired or forged link. */
  status: number;
  card: T | null;
}
