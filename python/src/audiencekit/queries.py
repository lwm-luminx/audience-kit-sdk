"""The GraphQL documents behind the typed calls: this SDK version's fragments, which ``models`` read.

Fragments with module fields take the audience's ``SchemaShape``: the API leaves a module's fields out of an audience
that hasn't installed it, and asking for one fails the whole operation.
"""

from __future__ import annotations

from .schema import SchemaShape

PAGE_FIELDS = "id name photoUrl bannerUrl"
TAG_FIELDS = "id name color"
MONEY_FIELDS = "cents currency"
ADMISSION_OFFER_FIELDS = f"price {{ {MONEY_FIELDS} }} url seller {{ key name }}"
COVER_CHARGE_FIELDS = (
    f"amount {{ {MONEY_FIELDS} }} fee {{ {MONEY_FIELDS} }} total {{ {MONEY_FIELDS} }} night from payable "
    "event { id name }"
)

LISTING_TYPES = ["Locale", "ListingProfile", "Venue", "Location", "Person", "Event"]
"""The types whose fields the listing documents depend on."""

EVENT_TYPES = [*LISTING_TYPES, "EventSeries", "EventTickets"]


def locale_fields(shape: SchemaShape) -> str:
    has_place = shape.has("Locale", "profile") and shape.has("ListingProfile", "places")
    places = " profile { places { placeId } }" if has_place else ""
    return f"id name label cityNames bannerUrl{places}"


def venue_fields(shape: SchemaShape) -> str:
    page = (
        f"profile {{ facebook {{ page {{ {PAGE_FIELDS} }} }} }}"
        if shape.has("Venue", "profile") and shape.has("ListingProfile", "facebook")
        else ""
    )
    place = " places { placeId }" if shape.has("Location", "places") else ""
    return (
        f"id name hidden order photoUrl bannerUrl {page} locale {{ {locale_fields(shape)} }} "
        f"location {{ id point address{place} }} tags {{ {TAG_FIELDS} }}"
    )


def person_venue_fields(shape: SchemaShape) -> str:
    friends = " friends { list { nodes { id name facebookId presence } } }" if shape.has("Venue", "friends") else ""
    return f"id name photoUrl locale {{ id name }}{friends}"


def person_event_fields(shape: SchemaShape) -> str:
    venue = f" venue {{ name venue {{ {person_venue_fields(shape)} }} }}" if shape.has("Event", "venue") else ""
    return f"id name startAt locale {{ id name }}{venue} tags {{ {TAG_FIELDS} }}"


AUDIENCE = """
query Audience {
  id name subdomain theme { preset tagline light { name value } dark { name value } }
}
"""

ME = """
query Me {
  me { self { id name firstName lastName emailAddress isAdmin presence } }
}
"""

NODE = """
query Node($id: ID!) {
  node(id: $id) { __typename id }
}
"""

TRIBES = f"""
query Tribes {{
  id tribes: tags(tribes: true) {{ {TAG_FIELDS} tribe }}
  me {{ self {{ id tribes {{ isPrivate tag {{ {TAG_FIELDS} tribe }} }} }} }}
}}
"""

IDENTIFY_WITH_TRIBE = f"""
mutation IdentifyWithTribe($tagId: ID!, $isPrivate: Boolean) {{
  identifyWithTribe(input: {{ tagId: $tagId, isPrivate: $isPrivate }}) {{
    tribes {{ isPrivate tag {{ {TAG_FIELDS} tribe }} }}
  }}
}}
"""

LEAVE_TRIBE = f"""
mutation LeaveTribe($tagId: ID!) {{
  leaveTribe(input: {{ tagId: $tagId }}) {{ tribes {{ isPrivate tag {{ {TAG_FIELDS} tribe }} }} }}
}}
"""

RSVP_EVENT = """
mutation RSVPEvent($eventId: ID!, $state: RSVPState!) {
  rsvpEvent(input: { eventId: $eventId, state: $state }) { event { id rsvp { mine } } }
}
"""

REGISTER_DEVICE = """
mutation RegisterDevice($notificationToken: String!, $appId: String, $sandbox: Boolean) {
  registerDevice(input: { notificationToken: $notificationToken, appId: $appId, sandbox: $sandbox }) { registered }
}
"""


def venues(shape: SchemaShape) -> str:
    return f"query Venues {{ venues {{ list {{ nodes {{ {venue_fields(shape)} }} }} }} }}"


def people(shape: SchemaShape) -> str:
    page = (
        f"profile {{ facebook {{ page {{ {PAGE_FIELDS} }} }} }}"
        if shape.has("Person", "profile") and shape.has("ListingProfile", "facebook")
        else ""
    )
    venues_part = f"venues {{ home {{ {person_venue_fields(shape)} }} }}" if shape.has("Person", "venues") else ""
    events_part = (
        "events { involvements { edges { relationship role via { id name } "
        f"node {{ {person_event_fields(shape)} }} }} }} }}"
        if shape.has("Person", "events")
        else ""
    )
    return (
        "query People { people { list { nodes { "
        f"id name avatarUrl bannerUrl order global likeRequired {page} {venues_part} "
        f"locales {{ id name }} {events_part} "
        f"tags {{ {TAG_FIELDS} }} }} }} }} }}"
    )


def locales(shape: SchemaShape) -> str:
    return f"query Locales {{ locales {{ {locale_fields(shape)} }} }}"


def closest_locale(shape: SchemaShape) -> str:
    return (
        f"query ClosestLocale($near: CoordinatesInput!) {{ closestLocale(near: $near) {{ {locale_fields(shape)} }} }}"
    )


def event_venue_fields(shape: SchemaShape) -> str:
    place = " places { placeId }" if shape.has("Location", "places") else ""
    return f"venue {{ name venue {{ id name photoUrl location {{ id point address{place} }} }} }}"


def event_tickets_fields(shape: SchemaShape) -> str:
    cover = f" cover {{ charge {{ {COVER_CHARGE_FIELDS} }} }}" if shape.has("EventTickets", "cover") else ""
    return f"tickets {{ url offers {{ nodes {{ {ADMISSION_OFFER_FIELDS} }} }}{cover} }}"


def event_fields(shape: SchemaShape) -> str:
    fields = (
        "id name description startAt endAt isFeatured isCanceled bannerUrl sourceUrl "
        f"locale {{ {locale_fields(shape)} }} tags {{ {TAG_FIELDS} }}"
    )
    if shape.has("Event", "venue"):
        fields += " " + event_venue_fields(shape)
    if shape.has("Event", "rsvp"):
        fields += " rsvp { mine count }"
    if shape.has("Event", "people"):
        fields += " people { hosts { nodes { id name avatarUrl } } lineup { nodes { id name avatarUrl } } }"
    if shape.has("Event", "tickets"):
        fields += " " + event_tickets_fields(shape)
    return fields


def event_series_fields(shape: SchemaShape) -> str:
    venue = " " + event_venue_fields(shape) if shape.has("EventSeries", "venue") else ""
    return (
        "id name description recurrenceText startsOn startTime timeZone durationMinutes bannerUrl "
        f"locale {{ {locale_fields(shape)} }} tags {{ {TAG_FIELDS} }}{venue}"
    )


def events(shape: SchemaShape) -> str:
    return (
        "query Events($window: EventWindow, $localeId: ID, $venueId: ID, $first: Int) { events { "
        "list(window: $window, localeId: $localeId, venueId: $venueId, first: $first) "
        f"{{ nodes {{ {event_fields(shape)} }} }} "
        "} }"
    )


def event(shape: SchemaShape) -> str:
    return f"query Event($id: ID!) {{ events {{ event(id: $id) {{ {event_fields(shape)} }} }} }}"


def event_series(shape: SchemaShape) -> str:
    return (
        "query EventSeries($localeId: ID, $venueId: ID, $first: Int) { events { "
        f"series(localeId: $localeId, venueId: $venueId, first: $first) {{ nodes {{ {event_series_fields(shape)} }} }} "
        "} }"
    )


def schema_fields(types: list[str]) -> str:
    """Introspection of which fields each of ``types`` has: ``t0: __type(name: "…") { fields { name } }``."""
    selections = " ".join(
        f't{index}: __type(name: "{name}") {{ fields(includeDeprecated: true) {{ name }} }}'
        for index, name in enumerate(types)
    )
    return f"query SchemaFields {{ {selections} }}"


# Members: RSVP, cover, chat

RSVP_FIELDS = "count mine mineSource"
PROFILE_FIELDS = "id name avatarUrl"
VENUE_COVER_CHARGE_FIELDS = (
    f"{COVER_CHARGE_FIELDS} "
    f"coatCheck {{ amount {{ {MONEY_FIELDS} }} fee {{ {MONEY_FIELDS} }} total {{ {MONEY_FIELDS} }} night payable }} "
    f"scale {{ min {{ {MONEY_FIELDS} }} max {{ {MONEY_FIELDS} }} suggested {{ {MONEY_FIELDS} }} }}"
)
"""A venue's cover tonight, with its coat check and sliding scale."""
ADMISSION_FIELDS = (
    f"id status kind night quantity tier claimCheckNumber amount {{ {MONEY_FIELDS} }} fee {{ {MONEY_FIELDS} }} "
    f"total {{ {MONEY_FIELDS} }} isRefundable passSecret scanCount checkedInAt createdAt "
    f"profile {{ {PROFILE_FIELDS} }} venue {{ id name photoUrl }} event {{ id name }}"
)
"""An ``Admission``, with the pass secret the buyer makes the door code from."""
PURCHASE_FIELDS = (
    f"admission {{ {ADMISSION_FIELDS} }} provider paymentIntentClientSecret publishableKey stripeAccountId "
    "squareApplicationId squareLocationId"
)
CHAT_MESSAGE_FIELDS = "id body message name userId avatarUrl photoUrl sentAt role kind title pinned"

VENUE_TICKET_TYPES = ["Venue", "VenueTickets"]

CANCEL_RSVP = f"""
mutation CancelRSVP($eventId: ID!) {{
  cancelRsvp(input: {{ eventId: $eventId }}) {{ event {{ id rsvp {{ {RSVP_FIELDS} }} }} }}
}}
"""

ADMISSIONS = f"""
query Admissions {{
  me {{ cover {{ admissions {{ nodes {{ {ADMISSION_FIELDS} }} }} }} }}
}}
"""


def venue_cover(shape: SchemaShape) -> str:
    """A venue's cover tonight and the signed-in person's pass; only the venue without Ticketing and Cover."""
    cover = (
        f" tickets {{ cover {{ charge {{ {VENUE_COVER_CHARGE_FIELDS} }} viewerAdmission {{ {ADMISSION_FIELDS} }} "
        f"viewerCoatCheck {{ {ADMISSION_FIELDS} }} }} }}"
        if shape.has("Venue", "tickets") and shape.has("VenueTickets", "cover")
        else ""
    )
    return f"query VenueCover($id: ID!) {{\n  venues {{ venue(id: $id) {{ id name{cover} }} }}\n}}"


BUY_COVER = f"""
mutation BuyCover($venueId: ID!, $amount: MoneyInput) {{
  buyCover(input: {{ venueId: $venueId, amount: $amount }}) {{ {PURCHASE_FIELDS} }}
}}
"""

BUY_COAT_CHECK = f"""
mutation BuyCoatCheck($venueId: ID!, $quantity: Int) {{
  buyCoatCheck(input: {{ venueId: $venueId, quantity: $quantity }}) {{ {PURCHASE_FIELDS} }}
}}
"""

PAY_COVER = f"""
mutation PayCover($admissionId: ID!, $sourceId: String!, $verificationToken: String) {{
  payCover(input: {{ admissionId: $admissionId, sourceId: $sourceId, verificationToken: $verificationToken }}) {{
    admission {{ {ADMISSION_FIELDS} }}
  }}
}}
"""

CONFIRM_COVER = f"""
mutation ConfirmCover($admissionId: ID!) {{
  confirmCover(input: {{ admissionId: $admissionId }}) {{ admission {{ {ADMISSION_FIELDS} }} }}
}}
"""

REFUND_ADMISSION = f"""
mutation RefundAdmission($admissionId: ID!) {{
  refundAdmission(input: {{ admissionId: $admissionId }}) {{ admission {{ {ADMISSION_FIELDS} }} }}
}}
"""

SEND_CHAT_MESSAGE = f"""
mutation SendMyChatMessage($input: ChatMessageSendOwnInput!) {{
  sendMyChatMessage(input: $input) {{ message {{ {CHAT_MESSAGE_FIELDS} }} }}
}}
"""

REMOVE_CHAT_MESSAGE = """
mutation RemoveMyChatMessage($messageId: ID!) {
  removeMyChatMessage(input: { messageId: $messageId }) { deletedId }
}
"""


# Soapbox (news)

SOAPBOX_TYPES = ["Audience", "Venue", "Event", "Person", "Locale", "Article", "Publication"]
"""The types the Soapbox documents depend on: the root's ``soapbox`` and each listing's ``articles``."""
PUBLICATION_SUMMARY_FIELDS = "id name photoUrl trusted acceptsOpEds"
ARTICLE_FIELDS = (
    "id slug title summary byline kind publishedAt edited pinned teaser canonicalUrl disclosure heroPhotoUrl "
    f"heroAltText publication {{ {PUBLICATION_SUMMARY_FIELDS} }}"
)
ARTICLE_SUBJECT_FIELDS = "venues { id name } events { id name } people { id name } locales { id name }"
PUBLICATION_FIELDS = (
    "id name masthead about websiteUrl photoUrl trusted acceptsOpEds opEdGuidelines locale { id name } "
    "person { id name }"
)
OP_ED_FIELDS = f"{ARTICLE_FIELDS} status reviewNote submittedAt"


def article_fields(shape: SchemaShape) -> str:
    """The article fields this audience's API has: the tip to read without ads came later."""
    if not shape.has("Article", "viewerAdFree") or not shape.has("Publication", "adFreeOffered"):
        return ARTICLE_FIELDS
    summary = f"{PUBLICATION_SUMMARY_FIELDS} adFreeOffered"
    return ARTICLE_FIELDS.replace(PUBLICATION_SUMMARY_FIELDS, summary) + " viewerAdFree"


def publication_fields(shape: SchemaShape) -> str:
    if not shape.has("Publication", "adFreeOffered"):
        return PUBLICATION_FIELDS
    return f"{PUBLICATION_FIELDS} adFreeOffered adFreeTipCents adFreeDays viewerAdFree viewerAdFreeUntil"


def _no_soapbox(name: str) -> str:
    """The document for an audience without Soapbox: asks for nothing the models read, under the operation's name."""
    return f"query {name} {{ id }}"


def articles(shape: SchemaShape) -> str:
    if not shape.has("Audience", "soapbox"):
        return _no_soapbox("Articles")
    return (
        "query Articles($localeId: ID, $publicationId: ID, $first: Int) {\n"
        "  soapbox { articles(localeId: $localeId, publicationId: $publicationId, first: $first) {\n"
        f"    nodes {{ {article_fields(shape)} }}\n  }} }}\n}}"
    )


def articles_page(shape: SchemaShape) -> str:
    if not shape.has("Audience", "soapbox"):
        return _no_soapbox("ArticlesPage")
    return (
        "query ArticlesPage($localeId: ID, $publicationId: ID, $first: Int, $after: String) {\n"
        "  soapbox { articles(localeId: $localeId, publicationId: $publicationId, first: $first, after: $after) {\n"
        f"    nodes {{ {article_fields(shape)} }}\n    pageInfo {{ endCursor hasNextPage }}\n  }} }}\n}}"
    )


def national_articles(shape: SchemaShape) -> str:
    if not shape.has("Audience", "soapbox") or not shape.has("Article", "featuredNationally"):
        return _no_soapbox("NationalArticles")
    return (
        "query NationalArticles($localeId: ID, $first: Int) {\n"
        "  soapbox { articles(national: true, localeId: $localeId, first: $first) {\n"
        f"    nodes {{ {article_fields(shape)} featuredNationally }}\n  }} }}\n}}"
    )


def article(shape: SchemaShape) -> str:
    if not shape.has("Audience", "soapbox"):
        return _no_soapbox("Article")
    return (
        "query Article($id: ID!) {\n"
        f"  soapbox {{ article(id: $id) {{ {article_fields(shape)} body {ARTICLE_SUBJECT_FIELDS} }} }}\n}}"
    )


def publications(shape: SchemaShape) -> str:
    if not shape.has("Audience", "soapbox"):
        return _no_soapbox("Publications")
    return f"query Publications {{\n  soapbox {{ publications {{ {publication_fields(shape)} }} }}\n}}"


def publication(shape: SchemaShape) -> str:
    if not shape.has("Audience", "soapbox"):
        return _no_soapbox("Publication")
    return f"query Publication($id: ID!) {{\n  soapbox {{ publication(id: $id) {{ {publication_fields(shape)} }} }}\n}}"


def my_op_eds(shape: SchemaShape) -> str:
    if not shape.has("Audience", "soapbox"):
        return _no_soapbox("MyOpEds")
    return f"query MyOpEds {{\n  soapbox {{ myOpEds {{ {OP_ED_FIELDS} }} }}\n}}"


ARTICLE_TOPICS = {
    "venue": ("Venue", "venues { venue(id: $id) { ", " } }"),
    "event": ("Event", "events { event(id: $id) { ", " } }"),
    "person": ("Person", "people { person(id: $id) { ", " } }"),
    "locale": ("Locale", "locale(id: $id) { ", " }"),
}
"""What an article can be about: the listing type, and how the document opens and closes around its articles."""


def articles_about(topic: str, shape: SchemaShape) -> str:
    """Live articles about a venue, event, person or locale ("In the news")."""
    type_name, open_, close = ARTICLE_TOPICS[topic]
    if not shape.has(type_name, "articles"):
        return _no_soapbox("ArticlesAbout")
    return (
        "query ArticlesAbout($id: ID!, $first: Int) {\n  "
        f"{open_}articles {{ list(first: $first) {{ nodes {{ {article_fields(shape)} }} }} }}{close}\n}}"
    )


SUBMIT_OP_ED = f"""
mutation SubmitOpEd($publicationId: ID!, $title: String!, $body: String!, $summary: String, $byline: String) {{
  submitOpEd(
    input: {{ publicationId: $publicationId, title: $title, body: $body, summary: $summary, byline: $byline }}
  ) {{
    article {{ {OP_ED_FIELDS} }}
  }}
}}
"""


# Calendar subscription

CALENDAR_FEED_FIELDS = "url webcalUrl googleUrl venues { id }"

CALENDAR_FEED = f"""
query CalendarFeed {{
  me {{ calendarFeed {{ {CALENDAR_FEED_FIELDS} }} }}
}}
"""

CREATE_CALENDAR_FEED = f"""
mutation CreateCalendarFeed($reset: Boolean) {{
  createCalendarFeed(input: {{ reset: $reset }}) {{ calendarFeed {{ {CALENDAR_FEED_FIELDS} }} }}
}}
"""

SET_CALENDAR_FEED_VENUE = f"""
mutation SetCalendarFeedVenue($venueId: ID!, $following: Boolean) {{
  setCalendarFeedVenue(input: {{ venueId: $venueId, following: $following }}) {{
    calendarFeed {{ {CALENDAR_FEED_FIELDS} }}
  }}
}}
"""

DELETE_CALENDAR_FEED = """
mutation DeleteCalendarFeed {
  deleteCalendarFeed(input: {}) { deleted }
}
"""


# Moderation and the account

REPORT_CONTENT = """
mutation ReportContent($targetType: ReportTarget!, $targetId: ID!, $reason: String, $block: Boolean) {
  reportContent(input: { targetType: $targetType, targetId: $targetId, reason: $reason, block: $block }) {
    reported
    blocked
  }
}
"""

BLOCK_USER = """
mutation BlockUser($userId: ID!) {
  blockUser(input: { userId: $userId }) { blockedUsers { id } }
}
"""

UNBLOCK_USER = """
mutation UnblockUser($userId: ID!) {
  unblockUser(input: { userId: $userId }) { blockedUsers { id } }
}
"""

DELETE_ACCOUNT = """
mutation DeleteAccount($confirm: Boolean!) {
  deleteAccount(input: { confirm: $confirm }) { deleted }
}
"""
