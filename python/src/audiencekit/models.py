"""The records the typed calls return: plain dataclasses built from the API's JSON.

Fields a module adds are ``None`` when the audience hasn't installed that module (or the query left them out).
Every model keeps the JSON it was built from as ``raw``, for fields the SDK doesn't type yet.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

JSON = dict[str, Any]


def parse_datetime(value: Any) -> datetime | None:
    """An ISO 8601 timestamp as the API sends it (``2026-11-06T20:00:00Z``), or ``None``."""
    if not isinstance(value, str) or not value:
        return None
    text = value[:-1] + "+00:00" if value.endswith("Z") else value
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        return None
    return parsed if parsed.tzinfo else parsed.replace(tzinfo=timezone.utc)


def _str(value: Any) -> str | None:
    return value if isinstance(value, str) else None


def _list(value: Any) -> list[Any] | None:
    return value if isinstance(value, list) else None


def _dict(value: Any) -> JSON | None:
    return value if isinstance(value, dict) else None


@dataclass(frozen=True)
class Coordinate:
    """A latitude and longitude in degrees."""

    latitude: float
    longitude: float

    @classmethod
    def from_wkt(cls, wkt: Any) -> Coordinate | None:
        """Parses a WKT point, ``POINT (<longitude> <latitude>)``, optionally with an SRID prefix. A point that isn't
        on Earth (NaN, infinity, out of range, often the two swapped) is ``None``."""
        if not isinstance(wkt, str):
            return None
        open_at, close_at = wkt.find("("), wkt.rfind(")")
        if open_at < 0 or close_at < open_at or "POINT" not in wkt[:open_at].upper():
            return None
        numbers: list[float] = []
        for part in wkt[open_at + 1 : close_at].split():
            try:
                numbers.append(float(part))
            except ValueError:
                continue
        if len(numbers) < 2:
            return None
        longitude, latitude = numbers[0], numbers[1]
        if not (-90 <= latitude <= 90 and -180 <= longitude <= 180):
            return None
        return cls(latitude=latitude, longitude=longitude)

    @property
    def wkt(self) -> str:
        """The point as WKT, the way the API serializes a ``Geography``."""
        return f"POINT ({self.longitude} {self.latitude})"

    def coordinates_input(self, beacon_major: int | None = None, beacon_minor: int | None = None) -> JSON:
        """The value to pass as a ``CoordinatesInput`` variable, with the iBeacon the device is near, if any."""
        value: JSON = {"latitude": self.latitude, "longitude": self.longitude}
        if beacon_major:
            value["beaconMajor"] = beacon_major
        if beacon_minor:
            value["beaconMinor"] = beacon_minor
        return value


@dataclass(frozen=True)
class Tag:
    """A tag on a venue, person or event: its name and chip color; ``tribe`` says whether people identify with it."""

    id: str
    name: str
    color: str | None = None
    tribe: bool | None = None
    raw: JSON = field(default_factory=dict, repr=False, compare=False)

    @classmethod
    def from_json(cls, data: JSON) -> Tag:
        return cls(
            id=str(data["id"]),
            name=str(data.get("name", "")),
            color=_str(data.get("color")),
            tribe=data.get("tribe"),
            raw=data,
        )


def _tags(value: Any) -> list[Tag] | None:
    items = _list(value)
    return None if items is None else [Tag.from_json(item) for item in items if isinstance(item, dict)]


@dataclass(frozen=True)
class Page:
    """A Facebook Page a venue or person is listed from."""

    id: str
    name: str
    photo_url: str | None = None
    banner_url: str | None = None

    @classmethod
    def from_json(cls, data: JSON) -> Page:
        return cls(
            id=str(data["id"]),
            name=str(data.get("name", "")),
            photo_url=_str(data.get("photoUrl")),
            banner_url=_str(data.get("bannerUrl")),
        )


def _page(profile: Any) -> Page | None:
    """The Facebook Page in a ``profile { facebook { page } }`` mixin."""
    page = _dict(((_dict(profile) or {}).get("facebook") or {}).get("page"))
    return Page.from_json(page) if page and "id" in page else None


def _place_id(holder: Any) -> str | None:
    """The Google place ID in a ``places { placeId }`` mixin."""
    return _str(((_dict(holder) or {}).get("places") or {}).get("placeId"))


@dataclass(frozen=True)
class Locale:
    """A locale: a city or region the audience lists venues in."""

    id: str
    name: str | None = None
    label: str | None = None
    city_names: list[str] | None = None
    banner_url: str | None = None
    google_place_id: str | None = None
    raw: JSON = field(default_factory=dict, repr=False, compare=False)

    @classmethod
    def from_json(cls, data: JSON) -> Locale:
        return cls(
            id=str(data["id"]),
            name=_str(data.get("name")),
            label=_str(data.get("label")),
            city_names=_list(data.get("cityNames")),
            banner_url=_str(data.get("bannerUrl")),
            google_place_id=_place_id(data.get("profile")),
            raw=data,
        )


def _locale(value: Any) -> Locale | None:
    data = _dict(value)
    return Locale.from_json(data) if data and "id" in data else None


@dataclass(frozen=True)
class Location:
    """Where a venue is: its point (decoded from the API's WKT), address and Google place ID."""

    id: str
    coordinate: Coordinate | None = None
    address: str | None = None
    google_place_id: str | None = None

    @classmethod
    def from_json(cls, data: JSON) -> Location:
        return cls(
            id=str(data["id"]),
            coordinate=Coordinate.from_wkt(data.get("point")),
            address=_str(data.get("address")),
            google_place_id=_place_id(data),
        )


def _location(value: Any) -> Location | None:
    data = _dict(value)
    return Location.from_json(data) if data and "id" in data else None


@dataclass(frozen=True)
class Venue:
    """A venue in the audience."""

    id: str
    name: str
    hidden: bool = False
    order: int = 0
    photo_url: str | None = None
    banner_url: str | None = None
    page: Page | None = None
    locale: Locale | None = None
    location: Location | None = None
    tags: list[Tag] | None = None
    raw: JSON = field(default_factory=dict, repr=False, compare=False)

    @classmethod
    def from_json(cls, data: JSON) -> Venue:
        page = _page(data.get("profile"))
        return cls(
            id=str(data["id"]),
            name=_str(data.get("name")) or (page.name if page else ""),
            hidden=bool(data.get("hidden", False)),
            order=int(data.get("order") or 0),
            photo_url=_str(data.get("photoUrl")),
            banner_url=_str(data.get("bannerUrl")),
            page=page,
            locale=_locale(data.get("locale")),
            location=_location(data.get("location")),
            tags=_tags(data.get("tags")),
            raw=data,
        )


@dataclass(frozen=True)
class Friend:
    """One of the signed-in user's friends, and whether they can be reached now."""

    id: str
    name: str | None = None
    facebook_id: str | None = None
    presence: str | None = None

    @classmethod
    def from_json(cls, data: JSON) -> Friend:
        return cls(
            id=str(data["id"]),
            name=_str(data.get("name")),
            facebook_id=_str(data.get("facebookId")),
            presence=_str(data.get("presence")),
        )


@dataclass(frozen=True)
class PersonVenue:
    """A person's home venue or gig venue, with which of the signed-in user's friends are there now (Friends)."""

    id: str
    name: str | None = None
    photo_url: str | None = None
    locale: Locale | None = None
    friends: list[Friend] | None = None

    @classmethod
    def from_json(cls, data: JSON) -> PersonVenue:
        nodes = _list(((_dict(data.get("friends")) or {}).get("list") or {}).get("nodes"))
        return cls(
            id=str(data["id"]),
            name=_str(data.get("name")),
            photo_url=_str(data.get("photoUrl")),
            locale=_locale(data.get("locale")),
            friends=None if nodes is None else [Friend.from_json(n) for n in nodes if isinstance(n, dict)],
        )


def _venue_mixin(value: Any) -> tuple[str | None, JSON | None]:
    """The events module's ``venue { name venue { … } }``: a display name and the venue, if any."""
    mixin = _dict(value)
    if mixin is None:
        return None, None
    venue = _dict(mixin.get("venue"))
    return _str(mixin.get("name")), venue if venue and "id" in venue else None


@dataclass(frozen=True)
class PersonEvent:
    """One of a person's events."""

    id: str
    name: str | None = None
    start_at: datetime | None = None
    locale: Locale | None = None
    venue: PersonVenue | None = None
    venue_name: str | None = None
    tags: list[Tag] | None = None

    @classmethod
    def from_json(cls, data: JSON) -> PersonEvent:
        venue_name, venue = _venue_mixin(data.get("venue"))
        return cls(
            id=str(data["id"]),
            name=_str(data.get("name")),
            start_at=parse_datetime(data.get("startAt")),
            locale=_locale(data.get("locale")),
            venue=PersonVenue.from_json(venue) if venue else None,
            venue_name=venue_name,
            tags=_tags(data.get("tags")),
        )


@dataclass(frozen=True)
class Troupe:
    """A group a person performs with."""

    id: str
    name: str | None = None


@dataclass(frozen=True)
class PersonEventInvolvement:
    """How a person is involved in an event: as a host or performer, and through which troupe."""

    event: PersonEvent
    relationship: str
    role: str | None = None
    via: Troupe | None = None

    @classmethod
    def from_json(cls, data: JSON) -> PersonEventInvolvement:
        via = _dict(data.get("via"))
        return cls(
            event=PersonEvent.from_json(data["node"]),
            relationship=str(data.get("relationship", "")),
            role=_str(data.get("role")),
            via=Troupe(id=str(via["id"]), name=_str(via.get("name"))) if via and "id" in via else None,
        )


@dataclass(frozen=True)
class Person:
    """A person in the audience: a DJ, performer, host or promoter."""

    id: str
    name: str
    avatar_url: str | None = None
    banner_url: str | None = None
    order: int = 0
    global_: bool = False
    like_required: bool = False
    page: Page | None = None
    home_venue: PersonVenue | None = None
    locales: list[Locale] | None = None
    event_involvements: list[PersonEventInvolvement] | None = None
    tags: list[Tag] | None = None
    raw: JSON = field(default_factory=dict, repr=False, compare=False)

    @property
    def events(self) -> list[PersonEvent] | None:
        """The person's events; ``None`` without the People module's events."""
        if self.event_involvements is None:
            return None
        return [involvement.event for involvement in self.event_involvements]

    @classmethod
    def from_json(cls, data: JSON) -> Person:
        page = _page(data.get("profile"))
        home = _dict((_dict(data.get("venues")) or {}).get("home"))
        locales = _list(data.get("locales"))
        edges = _list(((_dict(data.get("events")) or {}).get("involvements") or {}).get("edges"))
        return cls(
            id=str(data["id"]),
            name=_str(data.get("name")) or (page.name if page else ""),
            avatar_url=_str(data.get("avatarUrl")),
            banner_url=_str(data.get("bannerUrl")),
            order=int(data.get("order") or 0),
            global_=bool(data.get("global", False)),
            like_required=bool(data.get("likeRequired", False)),
            page=page,
            home_venue=PersonVenue.from_json(home) if home and "id" in home else None,
            locales=None if locales is None else [Locale.from_json(x) for x in locales if isinstance(x, dict)],
            event_involvements=None
            if edges is None
            else [
                PersonEventInvolvement.from_json(e)
                for e in edges
                if isinstance(e, dict) and isinstance(e.get("node"), dict)
            ],
            tags=_tags(data.get("tags")),
            raw=data,
        )


@dataclass(frozen=True)
class EventVenue:
    """A venue an event or series is at."""

    id: str
    name: str | None = None
    photo_url: str | None = None
    location: Location | None = None

    @classmethod
    def from_json(cls, data: JSON) -> EventVenue:
        return cls(
            id=str(data["id"]),
            name=_str(data.get("name")),
            photo_url=_str(data.get("photoUrl")),
            location=_location(data.get("location")),
        )


@dataclass(frozen=True)
class EventPerson:
    """Someone on an event's bill: a host or a performer on its lineup."""

    id: str
    name: str | None = None
    avatar_url: str | None = None

    @classmethod
    def from_json(cls, data: JSON) -> EventPerson:
        return cls(id=str(data["id"]), name=_str(data.get("name")), avatar_url=_str(data.get("avatarUrl")))


def _people(value: Any) -> list[EventPerson] | None:
    nodes = _list((_dict(value) or {}).get("nodes"))
    return None if nodes is None else [EventPerson.from_json(n) for n in nodes if isinstance(n, dict)]


@dataclass(frozen=True)
class Money:
    cents: int
    currency: str

    @classmethod
    def from_json(cls, data: JSON) -> Money:
        return cls(cents=int(data.get("cents") or 0), currency=str(data.get("currency", "USD")))


@dataclass(frozen=True)
class AdmissionOffer:
    """A way into an event on sale elsewhere: its price, link and seller."""

    price: Money | None
    url: str | None
    seller_key: str | None = None
    seller_name: str | None = None

    @classmethod
    def from_json(cls, data: JSON) -> AdmissionOffer:
        price, seller = _dict(data.get("price")), _dict(data.get("seller")) or {}
        return cls(
            price=Money.from_json(price) if price else None,
            url=_str(data.get("url")),
            seller_key=_str(seller.get("key")),
            seller_name=_str(seller.get("name")),
        )


@dataclass(frozen=True)
class CoverCharge:
    """The cover at a venue on a night."""

    amount: Money
    fee: Money
    total: Money
    night: str
    payable: bool
    from_: str | None = None
    event_id: str | None = None
    event_name: str | None = None

    @classmethod
    def from_json(cls, data: JSON) -> CoverCharge:
        event = _dict(data.get("event")) or {}
        return cls(
            amount=Money.from_json(_dict(data.get("amount")) or {}),
            fee=Money.from_json(_dict(data.get("fee")) or {}),
            total=Money.from_json(_dict(data.get("total")) or {}),
            night=str(data.get("night", "")),
            payable=bool(data.get("payable", False)),
            from_=_str(data.get("from")),
            event_id=_str(event.get("id")),
            event_name=_str(event.get("name")),
        )


@dataclass(frozen=True)
class RSVP:
    """The signed-in user's RSVP and how many are going."""

    mine: str
    count: int


@dataclass(frozen=True)
class Event:
    """An event in the audience: a night, a meetup or a conference.

    ``venue``/``venue_name`` need the Venues module, ``rsvp`` RSVP, ``hosts``/``lineup`` People, and
    ``ticket_url``/``ticket_offers``/``cover_charge`` Ticketing; each is ``None`` without it.
    """

    id: str
    name: str | None = None
    description: str | None = None
    start_at: datetime | None = None
    end_at: datetime | None = None
    is_featured: bool = False
    is_canceled: bool = False
    banner_url: str | None = None
    source_url: str | None = None
    locale: Locale | None = None
    tags: list[Tag] | None = None
    venue: EventVenue | None = None
    venue_name: str | None = None
    rsvp: RSVP | None = None
    hosts: list[EventPerson] | None = None
    lineup: list[EventPerson] | None = None
    ticket_url: str | None = None
    ticket_offers: list[AdmissionOffer] | None = None
    cover_charge: CoverCharge | None = None
    raw: JSON = field(default_factory=dict, repr=False, compare=False)

    @classmethod
    def from_json(cls, data: JSON) -> Event:
        venue_name, venue = _venue_mixin(data.get("venue"))
        rsvp = _dict(data.get("rsvp"))
        people = _dict(data.get("people"))
        tickets = _dict(data.get("tickets"))
        offers = _list(((tickets or {}).get("offers") or {}).get("nodes")) if tickets else None
        charge = _dict(((tickets or {}).get("cover") or {}).get("charge")) if tickets else None
        return cls(
            id=str(data["id"]),
            name=_str(data.get("name")),
            description=_str(data.get("description")),
            start_at=parse_datetime(data.get("startAt")),
            end_at=parse_datetime(data.get("endAt")),
            is_featured=bool(data.get("isFeatured", False)),
            is_canceled=bool(data.get("isCanceled", False)),
            banner_url=_str(data.get("bannerUrl")),
            source_url=_str(data.get("sourceUrl")),
            locale=_locale(data.get("locale")),
            tags=_tags(data.get("tags")),
            venue=EventVenue.from_json(venue) if venue else None,
            venue_name=venue_name,
            rsvp=RSVP(mine=str(rsvp.get("mine", "UNSURE")), count=int(rsvp.get("count") or 0)) if rsvp else None,
            hosts=_people(people.get("hosts")) if people else None,
            lineup=_people(people.get("lineup")) if people else None,
            ticket_url=_str(tickets.get("url")) if tickets else None,
            ticket_offers=None
            if offers is None
            else [AdmissionOffer.from_json(o) for o in offers if isinstance(o, dict)],
            cover_charge=CoverCharge.from_json(charge) if charge else None,
            raw=data,
        )


@dataclass(frozen=True)
class EventSeries:
    """A recurring event by name: a weekly party, a monthly show."""

    id: str
    name: str | None = None
    description: str | None = None
    recurrence_text: str | None = None
    starts_on: str | None = None
    start_time: str | None = None
    time_zone: str | None = None
    duration_minutes: int | None = None
    banner_url: str | None = None
    locale: Locale | None = None
    tags: list[Tag] | None = None
    venue: EventVenue | None = None
    venue_name: str | None = None
    raw: JSON = field(default_factory=dict, repr=False, compare=False)

    @classmethod
    def from_json(cls, data: JSON) -> EventSeries:
        venue_name, venue = _venue_mixin(data.get("venue"))
        duration = data.get("durationMinutes")
        return cls(
            id=str(data["id"]),
            name=_str(data.get("name")),
            description=_str(data.get("description")),
            recurrence_text=_str(data.get("recurrenceText")),
            starts_on=_str(data.get("startsOn")),
            start_time=_str(data.get("startTime")),
            time_zone=_str(data.get("timeZone")),
            duration_minutes=int(duration) if isinstance(duration, int) else None,
            banner_url=_str(data.get("bannerUrl")),
            locale=_locale(data.get("locale")),
            tags=_tags(data.get("tags")),
            venue=EventVenue.from_json(venue) if venue else None,
            venue_name=venue_name,
            raw=data,
        )


@dataclass(frozen=True)
class ThemeToken:
    name: str
    value: str


@dataclass(frozen=True)
class AudienceTheme:
    """The audience's design tokens for its light and dark looks."""

    preset: str
    tagline: str | None
    light: list[ThemeToken]
    dark: list[ThemeToken]

    @classmethod
    def from_json(cls, data: JSON) -> AudienceTheme:
        def tokens(value: Any) -> list[ThemeToken]:
            return [
                ThemeToken(str(t.get("name", "")), str(t.get("value", "")))
                for t in _list(value) or []
                if isinstance(t, dict)
            ]

        return cls(
            preset=str(data.get("preset", "")),
            tagline=_str(data.get("tagline")),
            light=tokens(data.get("light")),
            dark=tokens(data.get("dark")),
        )


@dataclass(frozen=True)
class Audience:
    """The audience the client speaks for."""

    id: str
    name: str
    subdomain: str
    theme: AudienceTheme | None = None
    raw: JSON = field(default_factory=dict, repr=False, compare=False)

    @classmethod
    def from_json(cls, data: JSON) -> Audience:
        theme = _dict(data.get("theme"))
        return cls(
            id=str(data["id"]),
            name=str(data.get("name", "")),
            subdomain=str(data.get("subdomain", "")),
            theme=AudienceTheme.from_json(theme) if theme else None,
            raw=data,
        )


@dataclass(frozen=True)
class SelfUser:
    """The signed-in user's own profile."""

    id: str
    name: str | None = None
    first_name: str | None = None
    last_name: str | None = None
    email_address: str | None = None
    is_admin: bool | None = None
    presence: str | None = None

    @classmethod
    def from_json(cls, data: JSON) -> SelfUser:
        return cls(
            id=str(data["id"]),
            name=_str(data.get("name")),
            first_name=_str(data.get("firstName")),
            last_name=_str(data.get("lastName")),
            email_address=_str(data.get("emailAddress")),
            is_admin=data.get("isAdmin"),
            presence=_str(data.get("presence")),
        )


@dataclass(frozen=True)
class TribeIdentification:
    """A tribe the signed-in user identifies with, and whether that's private."""

    tag: Tag
    is_private: bool

    @classmethod
    def from_json(cls, data: JSON) -> TribeIdentification:
        return cls(tag=Tag.from_json(data["tag"]), is_private=bool(data.get("isPrivate", False)))


@dataclass(frozen=True)
class Tribes:
    """The tribes people can identify with here, and the signed-in user's own."""

    available: list[Tag]
    mine: list[TribeIdentification]


@dataclass(frozen=True)
class Node:
    """Any record by ID: what type it is."""

    id: str
    typename: str | None = None


@dataclass(frozen=True)
class Branding:
    """An audience's public branding for a host, from ``GET /v1/branding``. ``raw`` has everything the API sent."""

    audience_id: str
    name: str | None = None
    facebook_app_id: str | None = None
    facebook_login_config_id: str | None = None
    raw: JSON = field(default_factory=dict, repr=False, compare=False)

    @classmethod
    def from_json(cls, data: JSON) -> Branding:
        audience = _dict(data.get("audience")) or {}
        facebook = _dict(data.get("facebook")) or {}
        return cls(
            audience_id=str(audience.get("id") or data.get("audienceId") or ""),
            name=_str(audience.get("name")) or _str(data.get("name")),
            facebook_app_id=_str(facebook.get("appId")) or _str(data.get("facebookAppId")),
            facebook_login_config_id=_str(facebook.get("loginConfigId")) or _str(data.get("facebookLoginConfigId")),
            raw=data,
        )
