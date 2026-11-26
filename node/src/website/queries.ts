// The GraphQL documents a consumer website (hotmess.social) sends, moved here from its src/lib/api.ts, safetyApi.ts and
// privacyChoices.ts so every app shares them. Each is validated against graphql/schema.graphql (test/schema.test.ts).
// Public so a site can reuse the field lists in its own operations.

/** A venue: its address, phone and Facebook Page live on its listing profile. */
export const VENUE_FIELDS = "id name distance description photoUrl bannerUrl profile { address phone facebook { facebookId link } }";
/** A person in an event's people: their Facebook Page lives on their listing profile. */
export const PERSON_FIELDS = "id name avatarUrl profile { facebook { facebookId link } }";
/** A friend out tonight. */
export const FRIEND_FIELDS = "id name avatarUrl facebookId";
/** An event, its venue and its people. */
export const EVENT_FIELDS = `id name startAt endAt facebookId bannerUrl rsvp { mine }
  venue { name venue { ${VENUE_FIELDS} } } people { hosts { nodes { ${PERSON_FIELDS} } } lineup { nodes { ${PERSON_FIELDS} } } }`;
/** A social or music link. */
export const LINK_FIELDS = "id handle provider url";

/**
 * Where you are: the venue when you're at one, else your locale and its nearest venues. Tonight's events and your
 * friends out come from the locale.
 */
export const now = `mutation ReportLocation($position: CoordinatesInput!) {
  reportLocation(input: { position: $position }) {
    venue { ${VENUE_FIELDS} }
    locale {
      id name label bannerUrl
      events { upcoming { nodes { ${EVENT_FIELDS} } } }
      friends { list { nodes { ${FRIEND_FIELDS} } } venues { nodes { venue { id } friendCount } } }
    }
    nearbyVenues { ${VENUE_FIELDS} }
  }
}`;

/** Which cities someone is in, for pages that open on their own city. */
export const whereAmI = `mutation WhereAmI($position: CoordinatesInput!) {
  reportLocation(input: { position: $position }) { locale { id label } locales { id label } }
}`;

export const venuePage = `query Venue($id: ID!) {
  venues { venue(id: $id) { ${VENUE_FIELDS} events { upcoming { nodes { ${EVENT_FIELDS} } } } ordering { url } } }
}`;

export const eventPage = `query Event($id: ID!) {
  events { event(id: $id) { ${EVENT_FIELDS} } }
}`;

export const personPage = `query Person($id: ID!) {
  people {
    person(id: $id) {
      ${PERSON_FIELDS} bannerUrl
      events { upcoming { nodes { ${EVENT_FIELDS} } } }
      profile { socialLinks { nodes { ${LINK_FIELDS} } } }
      music { links { nodes { ${LINK_FIELDS} } } tracks { nodes { id title provider providerUrl streamUrl artworkUrl } } }
    }
  }
}`;

/** A post as its shared link shows it to someone signed in: comments stay in the app. */
export const post = `query Post($id: ID!) {
  posts {
    post(id: $id) {
      id body posterName posterAvatarUrl actingPersonName createdAt edited
      photos { url altText } event { id name startAt } person { id } venue { id }
    }
  }
}`;

// The poster builder looks a venue up by name, then fills the poster from it or from one of its nights: a one-off
// event, or a whole recurring series (never one date of a series).
export const POSTER_VENUE_FIELDS = "id name locale { name } profile { address }";
export const POSTER_SERIES_FIELDS = "id name recurrenceText startTime timeZone";
export const POSTER_EVENT_FIELDS = `id name startAt endAt venue { name venue { id name locale { name } } } eventSeries { ${POSTER_SERIES_FIELDS} }`;

export const posterSearch = `query PosterSearch($search: String!) {
  venues { list(search: $search, first: 8) { nodes { ${POSTER_VENUE_FIELDS} } } }
}`;

export const posterNights = `query PosterNights($id: ID!) {
  venues { venue(id: $id) { events { upcoming(first: 50) { nodes { ${POSTER_EVENT_FIELDS} } } } } }
}`;

export const posterSeries = `query PosterSeries($id: ID!) {
  events { eventSeries(id: $id) { ${POSTER_SERIES_FIELDS} events { ${POSTER_EVENT_FIELDS} } } }
}`;

export const posterVenue = `query PosterVenue($id: ID!) {
  venues { venue(id: $id) { ${POSTER_VENUE_FIELDS} } }
}`;

/** An event for a poster, and the share link its QR code opens, signed to open for a year. */
export const posterEvent = `query PosterEvent($id: ID!, $path: String!) {
  events { event(id: $id) { ${POSTER_EVENT_FIELDS} } }
  shareLink(path: $path, lifetime: YEAR) { url }
}`;

export const posterCover = `query PosterCover($id: ID!) {
  venues { venue(id: $id) { id tickets { cover { cents payable } } } }
}`;

export const printSafetyPoster = `mutation PrintSafetyPoster($venueId: ID!) {
  printSafetyPoster(input: { venueId: $venueId }) { safetyPoster { code url } }
}`;

// Safety alerts (audience-kit api/doc/SAFETY_ALERTS.md). Each read is its own request, so an API without these fields
// still shows the venue.

export const SAFETY_ALERT_FIELDS = `id state place concerns description summary seen acknowledgedByName acknowledgedAt escalatedAt closedAt
  supportSharedAt supportNote createdAt venue { id name } messages { id body fromStaff senderName createdAt }`;

export const venueSafety = `query VenueSafety($id: ID!) {
  venues { venue(id: $id) { id point canSendSafetyAlert safetyStaffOnShift } }
}`;

export const sendSafetyAlert = `mutation SendSafetyAlert($venueId: ID!, $place: SafetyAlertPlace, $concerns: [SafetyAlertConcern!], $description: String) {
  sendSafetyAlert(input: { venueId: $venueId, place: $place, concerns: $concerns, description: $description }) { safetyAlert { ${SAFETY_ALERT_FIELDS} } }
}`;

export const updateSafetyAlert = `mutation UpdateSafetyAlert($id: ID!, $place: SafetyAlertPlace, $concerns: [SafetyAlertConcern!], $description: String) {
  updateSafetyAlert(input: { id: $id, place: $place, concerns: $concerns, description: $description }) { safetyAlert { ${SAFETY_ALERT_FIELDS} } }
}`;

export const remindSafetyAlert = `mutation RemindSafetyAlert($id: ID!) {
  remindSafetyAlert(input: { id: $id }) { safetyAlert { ${SAFETY_ALERT_FIELDS} } }
}`;

export const cancelSafetyAlert = `mutation CancelSafetyAlert($id: ID!) {
  cancelSafetyAlert(input: { id: $id }) { safetyAlert { ${SAFETY_ALERT_FIELDS} } }
}`;

export const sendSafetyAlertMessage = `mutation SendSafetyAlertMessage($id: ID!, $body: String!) {
  sendSafetyAlertMessage(input: { id: $id, body: $body }) { safetyAlert { ${SAFETY_ALERT_FIELDS} } }
}`;

export const safetyAlert = `query SafetyAlert($id: ID!) {
  me { safetyAlert(id: $id) { ${SAFETY_ALERT_FIELDS} } }
}`;

export const mySafetyAlerts = `query MySafetyAlerts {
  me { safetyAlerts { ${SAFETY_ALERT_FIELDS} } }
}`;

export const supportResources = `query SupportResources($region: String) {
  supportResources(region: $region) { region name emergency checkedAt lines { id name description phone textNumber textBody url } }
}`;

/** Its own request, so an API older than ride links still shows the lines. */
export const supportRides = `query SupportRides($region: String) {
  supportResources(region: $region) { rides { id name url pickupUrl } }
}`;

// Privacy choices (the API's doc/PRIVACY_CHOICES.md).

export const PRIVACY_CHOICES_FIELDS =
  "saleShareOptedOut saleShareOptOutSource adMeasurement countedInAdMeasurement personalizedAds mayShare privacyPassUntil";

export const privacy = `query Privacy { privacyOffer { choices passCents passDays } me { privacy { ${PRIVACY_CHOICES_FIELDS} } } }`;

export const updatePrivacyChoices = `mutation UpdatePrivacyChoices($saleShareOptOut: Boolean, $adMeasurement: Boolean, $personalizedAds: Boolean) {
  updatePrivacyChoices(input: { saleShareOptOut: $saleShareOptOut, adMeasurement: $adMeasurement, personalizedAds: $personalizedAds }) {
    privacy { ${PRIVACY_CHOICES_FIELDS} }
  }
}`;

export const startPrivacyPass = `mutation StartPrivacyPass($returnUrl: String) {
  startPrivacyPass(input: { returnUrl: $returnUrl }) { checkoutUrl passId }
}`;

/** Whether a session is signed in to the audience: the API answers `me` for it. */
export const viewer = "query Viewer { me { self { id } } }";
