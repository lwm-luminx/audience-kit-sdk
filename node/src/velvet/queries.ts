// The GraphQL a Velvet TV screen sends, on its venue device's staff endpoint (/v1/audience/:id/staffql and the cable's
// "staffql" view): only what the board reads. Android's Google TV sends the same fields (VelvetQueries in staff-kit).

const messageFields = `
  id message body name avatarUrl endsAt sentAt kind title photoUrl pinned postedAsVenue automatic
`;

const appearanceFields = `
  id kind role title position startTiming state startsAt
  person { id name avatarUrl } people { nodes { id name avatarUrl } }
  songRequest { id title }
`;

/** The venue: its name, photos, time zone and upcoming events (tonight's are on the board). */
export const venue = `query VelvetTvVenue($id: ID!) { venues { venue(id: $id) {
  id name photoUrl bannerUrl
  tickets { cover { timeZone } }
  upcomingEvents: events { upcoming { nodes { id name startAt endAt isCanceled } } }
} } }`;

/** The night's running order, in the venue's service night. */
export const night = `query VelvetTvNight($id: ID!, $night: ISO8601Date) { venues { venue(id: $id) {
  people { runningOrder(night: $night) { nodes { ${appearanceFields} } } }
} } }`;

/** The venue's TV slogan settings, with its audience's posters and the ones it turned off. */
export const marqueePosters = `query VelvetTvMarqueePosters($id: ID!) { venues { venue(id: $id) {
  marqueeSlogans adultVenue marqueeHiddenSlogans marqueePosters { id image adult }
} } }`;

const displayFields = `id name kind off nowPlaying ranking { type slideshowId slideId seconds photos chatSize }`;

/** This screen's display, made the first time with the default ranking. */
export const registerDisplay = `mutation VelvetTvDisplayRegister($name: String, $kind: VenueDisplayKind) {
  registerVenueDisplay(input: { name: $name, kind: $kind }) { display { ${displayFields} } }
}`;

/** Every change to this screen's display. */
export const displaySubscription = `subscription VelvetTvDisplay($id: ID!) { venueDisplay(id: $id) { ${displayFields} } }`;

/** The venue's chat room as the TV follows it. */
export const chatSubscription = `subscription VelvetTvChat($id: ID!) {
  venueChat(venueId: $id) {
    __typename
    ... on ChatJoined {
      expiresBefore
      history { message { ... on VenueMessage { ${messageFields} } } }
      pinnedPost: pinnedMessage { message { ... on VenueMessage { ${messageFields} } } }
    }
    ... on ChatMessagePosted { message { ... on VenueMessage { ${messageFields} } } }
    ... on ChatMessageUpdated { message { ... on VenueMessage { ${messageFields} } } }
    ... on ChatMessageRemoved { messageId }
    ... on ChatPinChanged { messageId isPinned: pinned announcement { ... on VenueMessage { ${messageFields} } } }
    ... on ChatRoomCleared { clearedAt expired }
    ... on ChatLeft { reason }
  }
}`;
