"""The typed calls as data: a document, its variables, and how to read the answer. Both clients run them."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from typing import Any, Generic, TypeVar

from . import queries
from .models import (
    JSON,
    Audience,
    Coordinate,
    Event,
    EventSeries,
    Locale,
    Node,
    Person,
    SelfUser,
    Tag,
    TribeIdentification,
    Tribes,
    Venue,
)
from .schema import SchemaShape

T = TypeVar("T")


@dataclass(frozen=True)
class Operation(Generic[T]):
    """A GraphQL operation and how to turn its ``data`` into a value.

    ``document`` is the document itself, or a function of the audience's ``SchemaShape`` when it has module fields
    (``types`` then names the types to ask the schema about when the API refuses a field).
    """

    name: str
    document: str | Callable[[SchemaShape], str]
    decode: Callable[[JSON], T]
    variables: JSON | None = None
    types: list[str] | None = None

    def text(self, shape: SchemaShape) -> str:
        return self.document if isinstance(self.document, str) else self.document(shape)


def _nodes(data: Any, *path: str) -> list[JSON]:
    """The ``nodes`` list at ``path`` in ``data``, or ``[]`` when any step is missing."""
    value: Any = data
    for key in path:
        value = value.get(key) if isinstance(value, dict) else None
    return [item for item in value if isinstance(item, dict)] if isinstance(value, list) else []


def audience() -> Operation[Audience]:
    return Operation("Audience", queries.AUDIENCE, Audience.from_json)


def venues() -> Operation[list[Venue]]:
    return Operation(
        "Venues",
        queries.venues,
        lambda d: [Venue.from_json(v) for v in _nodes(d, "venues", "list", "nodes")],
        types=queries.LISTING_TYPES,
    )


def people() -> Operation[list[Person]]:
    return Operation(
        "People",
        queries.people,
        lambda d: [Person.from_json(p) for p in _nodes(d, "people", "list", "nodes")],
        types=queries.LISTING_TYPES,
    )


def locales() -> Operation[list[Locale]]:
    return Operation(
        "Locales",
        queries.locales,
        lambda d: [Locale.from_json(x) for x in _nodes(d, "locales")],
        types=queries.LISTING_TYPES,
    )


def closest_locale(position: Coordinate, beacon_major: int | None = None) -> Operation[Locale | None]:
    def decode(d: JSON) -> Locale | None:
        locale = d.get("closestLocale")
        return Locale.from_json(locale) if isinstance(locale, dict) else None

    return Operation(
        "ClosestLocale",
        queries.closest_locale,
        decode,
        variables={"near": position.coordinates_input(beacon_major=beacon_major)},
        types=queries.LISTING_TYPES,
    )


def me() -> Operation[SelfUser | None]:
    def decode(d: JSON) -> SelfUser | None:
        profile = (d.get("me") or {}).get("self") if isinstance(d.get("me"), dict) else None
        return SelfUser.from_json(profile) if isinstance(profile, dict) else None

    return Operation("Me", queries.ME, decode)


def node(id: str) -> Operation[Node | None]:
    def decode(d: JSON) -> Node | None:
        found = d.get("node")
        return Node(id=str(found["id"]), typename=found.get("__typename")) if isinstance(found, dict) else None

    return Operation("Node", queries.NODE, decode, variables={"id": id})


def _tribe_list(value: Any) -> list[TribeIdentification]:
    return [TribeIdentification.from_json(t) for t in value if isinstance(t, dict)] if isinstance(value, list) else []


def tribes() -> Operation[Tribes]:
    def decode(d: JSON) -> Tribes:
        me_ = d.get("me")
        profile = me_.get("self") if isinstance(me_, dict) else None
        if not isinstance(profile, dict):
            profile = {}
        available = [Tag.from_json(t) for t in d.get("tribes") or [] if isinstance(t, dict)]
        return Tribes(available=available, mine=_tribe_list(profile.get("tribes")))

    return Operation("Tribes", queries.TRIBES, decode)


def identify_with_tribe(tag_id: str, is_private: bool | None = None) -> Operation[list[TribeIdentification]]:
    variables: JSON = {"tagId": tag_id}
    if is_private is not None:
        variables["isPrivate"] = is_private
    return Operation(
        "IdentifyWithTribe",
        queries.IDENTIFY_WITH_TRIBE,
        lambda d: _tribe_list((d.get("identifyWithTribe") or {}).get("tribes")),
        variables=variables,
    )


def leave_tribe(tag_id: str) -> Operation[list[TribeIdentification]]:
    return Operation(
        "LeaveTribe",
        queries.LEAVE_TRIBE,
        lambda d: _tribe_list((d.get("leaveTribe") or {}).get("tribes")),
        variables={"tagId": tag_id},
    )


def rsvp_event(event_id: str, state: str) -> Operation[str]:
    def decode(d: JSON) -> str:
        payload = d.get("rsvpEvent") or {}
        return str(((payload.get("event") or {}).get("rsvp") or {}).get("mine") or state)

    return Operation("RSVPEvent", queries.RSVP_EVENT, decode, variables={"eventId": event_id, "state": state})


def register_device(token: str, app_id: str | None = None, sandbox: bool | None = None) -> Operation[bool]:
    variables: JSON = {"notificationToken": token}
    if app_id is not None:
        variables["appId"] = app_id
    if sandbox is not None:
        variables["sandbox"] = sandbox
    return Operation(
        "RegisterDevice",
        queries.REGISTER_DEVICE,
        lambda d: bool((d.get("registerDevice") or {}).get("registered", False)),
        variables=variables,
    )


def events(
    window: str = "UPCOMING", locale_id: str | None = None, venue_id: str | None = None, first: int = 100
) -> Operation[list[Event]]:
    variables: JSON = {"window": window, "first": first}
    if locale_id is not None:
        variables["localeId"] = locale_id
    if venue_id is not None:
        variables["venueId"] = venue_id
    return Operation(
        "Events",
        queries.events,
        lambda d: [Event.from_json(e) for e in _nodes(d, "events", "list", "nodes")],
        variables=variables,
        types=queries.EVENT_TYPES,
    )


def event(id: str) -> Operation[Event | None]:
    def decode(d: JSON) -> Event | None:
        found = (d.get("events") or {}).get("event") if isinstance(d.get("events"), dict) else None
        return Event.from_json(found) if isinstance(found, dict) else None

    return Operation("Event", queries.event, decode, variables={"id": id}, types=queries.EVENT_TYPES)


def event_series(
    locale_id: str | None = None, venue_id: str | None = None, first: int = 100
) -> Operation[list[EventSeries]]:
    variables: JSON = {"first": first}
    if locale_id is not None:
        variables["localeId"] = locale_id
    if venue_id is not None:
        variables["venueId"] = venue_id
    return Operation(
        "EventSeries",
        queries.event_series,
        lambda d: [EventSeries.from_json(s) for s in _nodes(d, "events", "series", "nodes")],
        variables=variables,
        types=queries.EVENT_TYPES,
    )
