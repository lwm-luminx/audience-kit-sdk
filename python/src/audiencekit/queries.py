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
