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
class CoatCheck:
    """A venue's coat check on a night, per coat."""

    amount: Money
    fee: Money
    total: Money
    night: str
    payable: bool

    @classmethod
    def from_json(cls, data: JSON) -> CoatCheck:
        return cls(
            amount=Money.from_json(_dict(data.get("amount")) or {}),
            fee=Money.from_json(_dict(data.get("fee")) or {}),
            total=Money.from_json(_dict(data.get("total")) or {}),
            night=str(data.get("night", "")),
            payable=bool(data.get("payable", False)),
        )


@dataclass(frozen=True)
class CoverCharge:
    """The cover at a venue on a night. ``scale_*`` are set on a sliding scale, ``coat_check`` when it has one (both
    only in ``venue_cover``)."""

    amount: Money
    fee: Money
    total: Money
    night: str
    payable: bool
    from_: str | None = None
    event_id: str | None = None
    event_name: str | None = None
    coat_check: CoatCheck | None = None
    scale_min: Money | None = None
    scale_max: Money | None = None
    scale_suggested: Money | None = None

    @property
    def is_sliding_scale(self) -> bool:
        return self.scale_min is not None and self.scale_max is not None

    @classmethod
    def from_json(cls, data: JSON) -> CoverCharge:
        event = _dict(data.get("event")) or {}
        coat = _dict(data.get("coatCheck"))
        scale = _dict(data.get("scale")) or {}

        def money(value: Any) -> Money | None:
            found = _dict(value)
            return Money.from_json(found) if found else None

        return cls(
            amount=Money.from_json(_dict(data.get("amount")) or {}),
            fee=Money.from_json(_dict(data.get("fee")) or {}),
            total=Money.from_json(_dict(data.get("total")) or {}),
            night=str(data.get("night", "")),
            payable=bool(data.get("payable", False)),
            from_=_str(data.get("from")),
            event_id=_str(event.get("id")),
            event_name=_str(event.get("name")),
            coat_check=CoatCheck.from_json(coat) if coat else None,
            scale_min=money(scale.get("min")),
            scale_max=money(scale.get("max")),
            scale_suggested=money(scale.get("suggested")),
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


# Members: cover and chat


@dataclass(frozen=True)
class Admission:
    """A cover or coat check pass. ``pass_secret`` (the buyer's only) makes the door code: ``cover_pass_code()``."""

    id: str
    status: str
    kind: str = "COVER"
    night: str | None = None
    quantity: int = 1
    tier: str | None = None
    claim_check_number: int | None = None
    amount: Money | None = None
    fee: Money | None = None
    total: Money | None = None
    is_refundable: bool = False
    pass_secret: str | None = None
    scan_count: int = 0
    checked_in_at: datetime | None = None
    created_at: datetime | None = None
    venue_id: str | None = None
    venue_name: str | None = None
    event_id: str | None = None
    event_name: str | None = None
    raw: JSON = field(default_factory=dict, repr=False, compare=False)

    @property
    def is_paid(self) -> bool:
        return self.status == "PAID"

    @classmethod
    def from_json(cls, data: JSON) -> Admission:
        venue, event = _dict(data.get("venue")) or {}, _dict(data.get("event")) or {}

        def money(key: str) -> Money | None:
            found = _dict(data.get(key))
            return Money.from_json(found) if found else None

        claim = data.get("claimCheckNumber")
        return cls(
            id=str(data["id"]),
            status=str(data.get("status", "PENDING")),
            kind=str(data.get("kind") or "COVER"),
            night=_str(data.get("night")),
            quantity=int(data.get("quantity") or 1),
            tier=_str(data.get("tier")),
            claim_check_number=claim if isinstance(claim, int) else None,
            amount=money("amount"),
            fee=money("fee"),
            total=money("total"),
            is_refundable=bool(data.get("isRefundable", False)),
            pass_secret=_str(data.get("passSecret")),
            scan_count=int(data.get("scanCount") or 0),
            checked_in_at=parse_datetime(data.get("checkedInAt")),
            created_at=parse_datetime(data.get("createdAt")),
            venue_id=_str(venue.get("id")),
            venue_name=_str(venue.get("name")),
            event_id=_str(event.get("id")),
            event_name=_str(event.get("name")),
            raw=data,
        )


@dataclass(frozen=True)
class CoverPurchase:
    """What ``buy_cover`` returns: the pass, and what Stripe's payment sheet or Square's SDK needs to pay it."""

    admission: Admission
    provider: str | None = None
    payment_intent_client_secret: str | None = None
    publishable_key: str | None = None
    stripe_account_id: str | None = None
    square_application_id: str | None = None
    square_location_id: str | None = None

    @property
    def is_square(self) -> bool:
        return self.provider == "SQUARE"

    @classmethod
    def from_json(cls, data: JSON) -> CoverPurchase:
        return cls(
            admission=Admission.from_json(_dict(data.get("admission")) or {"id": ""}),
            provider=_str(data.get("provider")),
            payment_intent_client_secret=_str(data.get("paymentIntentClientSecret")),
            publishable_key=_str(data.get("publishableKey")),
            stripe_account_id=_str(data.get("stripeAccountId")),
            square_application_id=_str(data.get("squareApplicationId")),
            square_location_id=_str(data.get("squareLocationId")),
        )


@dataclass(frozen=True)
class VenueCover:
    """A venue's cover tonight and the signed-in person's pass and coat check for it. ``charge`` is ``None`` when
    there's no cover tonight, or the audience doesn't have Ticketing and Cover."""

    id: str
    name: str | None = None
    charge: CoverCharge | None = None
    viewer_admission: Admission | None = None
    viewer_coat_check: Admission | None = None

    @classmethod
    def from_json(cls, data: JSON) -> VenueCover:
        cover = _dict((_dict(data.get("tickets")) or {}).get("cover")) or {}
        charge, admission, coat = (_dict(cover.get(k)) for k in ("charge", "viewerAdmission", "viewerCoatCheck"))
        return cls(
            id=str(data["id"]),
            name=_str(data.get("name")),
            charge=CoverCharge.from_json(charge) if charge else None,
            viewer_admission=Admission.from_json(admission) if admission else None,
            viewer_coat_check=Admission.from_json(coat) if coat else None,
        )


@dataclass(frozen=True)
class ChatMessage:
    """A message in a venue's or locale's chat."""

    id: str
    body: str | None = None
    name: str | None = None
    user_id: str | None = None
    avatar_url: str | None = None
    photo_url: str | None = None
    sent_at: datetime | None = None
    role: str | None = None
    kind: str | None = None
    title: str | None = None
    pinned: bool = False

    @classmethod
    def from_json(cls, data: JSON) -> ChatMessage:
        return cls(
            id=str(data["id"]),
            body=_str(data.get("body")) or _str(data.get("message")),
            name=_str(data.get("name")),
            user_id=_str(data.get("userId")),
            avatar_url=_str(data.get("avatarUrl")),
            photo_url=_str(data.get("photoUrl")),
            sent_at=parse_datetime(data.get("sentAt")),
            role=_str(data.get("role")),
            kind=_str(data.get("kind")),
            title=_str(data.get("title")),
            pinned=bool(data.get("pinned", False)),
        )


# Soapbox (news)


@dataclass(frozen=True)
class Subject:
    """A listing an article is about, or a publication's locale or person: its ID and name."""

    id: str
    name: str | None = None

    @classmethod
    def list(cls, value: Any) -> list[Subject]:
        return [cls(id=str(v["id"]), name=_str(v.get("name"))) for v in _list(value) or [] if isinstance(v, dict)]


@dataclass(frozen=True)
class Publication:
    """A Soapbox publication: a paper, a blog, a person's column. Articles carry only its summary fields."""

    id: str
    name: str
    photo_url: str | None = None
    trusted: bool = False
    accepts_op_eds: bool = False
    masthead: str | None = None
    about: str | None = None
    website_url: str | None = None
    op_ed_guidelines: str | None = None
    locale: Subject | None = None
    person: Subject | None = None
    ad_free_offered: bool = False
    ad_free_tip_cents: int | None = None
    ad_free_days: int | None = None

    @classmethod
    def from_json(cls, data: JSON) -> Publication:
        locale, person = _dict(data.get("locale")), _dict(data.get("person"))
        tip, days = data.get("adFreeTipCents"), data.get("adFreeDays")
        return cls(
            id=str(data["id"]),
            name=str(data.get("name") or ""),
            photo_url=_str(data.get("photoUrl")),
            trusted=bool(data.get("trusted", False)),
            accepts_op_eds=bool(data.get("acceptsOpEds", False)),
            masthead=_str(data.get("masthead")),
            about=_str(data.get("about")),
            website_url=_str(data.get("websiteUrl")),
            op_ed_guidelines=_str(data.get("opEdGuidelines")),
            locale=Subject(str(locale["id"]), _str(locale.get("name"))) if locale else None,
            person=Subject(str(person["id"]), _str(person.get("name"))) if person else None,
            ad_free_offered=bool(data.get("adFreeOffered", False)),
            ad_free_tip_cents=tip if isinstance(tip, int) else None,
            ad_free_days=days if isinstance(days, int) else None,
        )


@dataclass(frozen=True)
class Article:
    """A Soapbox article. ``body`` (Markdown) and what it's about come with ``article(id)``, not in lists; a
    ``teaser`` carries only the start, so link ``canonical_url`` for the rest."""

    id: str
    slug: str
    title: str
    byline: str
    kind: str
    publication: Publication
    summary: str | None = None
    published_at: datetime | None = None
    edited: bool = False
    pinned: bool = False
    teaser: bool = False
    canonical_url: str | None = None
    disclosure: str | None = None
    hero_photo_url: str | None = None
    hero_alt_text: str | None = None
    featured_nationally: bool = False
    viewer_ad_free: bool = False
    body: str | None = None
    venues: list[Subject] = field(default_factory=list)
    events: list[Subject] = field(default_factory=list)
    people: list[Subject] = field(default_factory=list)
    locales: list[Subject] = field(default_factory=list)
    status: str | None = None
    review_note: str | None = None
    submitted_at: datetime | None = None
    raw: JSON = field(default_factory=dict, repr=False, compare=False)

    @classmethod
    def from_json(cls, data: JSON) -> Article:
        return cls(
            id=str(data["id"]),
            slug=str(data.get("slug") or ""),
            title=str(data.get("title") or ""),
            byline=str(data.get("byline") or ""),
            kind=str(data.get("kind") or ""),
            publication=Publication.from_json(_dict(data.get("publication")) or {"id": "", "name": ""}),
            summary=_str(data.get("summary")),
            published_at=parse_datetime(data.get("publishedAt")),
            edited=bool(data.get("edited", False)),
            pinned=bool(data.get("pinned", False)),
            teaser=bool(data.get("teaser", False)),
            canonical_url=_str(data.get("canonicalUrl")),
            disclosure=_str(data.get("disclosure")),
            hero_photo_url=_str(data.get("heroPhotoUrl")),
            hero_alt_text=_str(data.get("heroAltText")),
            featured_nationally=bool(data.get("featuredNationally", False)),
            viewer_ad_free=bool(data.get("viewerAdFree", False)),
            body=_str(data.get("body")),
            venues=Subject.list(data.get("venues")),
            events=Subject.list(data.get("events")),
            people=Subject.list(data.get("people")),
            locales=Subject.list(data.get("locales")),
            status=_str(data.get("status")),
            review_note=_str(data.get("reviewNote")),
            submitted_at=parse_datetime(data.get("submittedAt")),
            raw=data,
        )


@dataclass(frozen=True)
class ArticlesPage:
    """A page of articles, with the cursor for the next (``articles_page``)."""

    articles: list[Article]
    end_cursor: str | None = None
    has_next_page: bool = False


@dataclass(frozen=True)
class CalendarFeed:
    """The signed-in person's calendar subscription: every event they're going to and every event at venues they
    follow. Treat ``url`` as a secret: anyone with it sees their plans."""

    url: str
    webcal_url: str
    google_url: str
    venue_ids: list[str] = field(default_factory=list)

    def follows(self, venue_id: str) -> bool:
        return venue_id in self.venue_ids

    @classmethod
    def from_json(cls, data: JSON) -> CalendarFeed:
        return cls(
            url=str(data.get("url") or ""),
            webcal_url=str(data.get("webcalUrl") or ""),
            google_url=str(data.get("googleUrl") or ""),
            venue_ids=[s.id for s in Subject.list(data.get("venues"))],
        )


# Moderation

REPORT_TARGETS = ("MESSAGE", "PERSON", "PHOTO", "PING", "PRIVATE_MESSAGE", "POST", "POST_COMMENT", "VENUE")
"""What ``report_content`` reports, as the API's ``ReportTarget`` names it."""

INTIMATE_IMAGE_REASON = "Intimate image shared without consent"
"""The reason for an intimate image shared without consent. The API gives a report with it a 48-hour deadline (the US
Take It Down Act), so keep the wording."""

REPORT_REASONS = ("Spam", "Harassment or hate", "Sexual content", INTIMATE_IMAGE_REASON, "Scam or fraud", "Other")
"""The reasons to offer when someone reports something, worded as the other SDKs word them."""


@dataclass(frozen=True)
class ReportResult:
    reported: bool
    blocked: bool


# Public listings (REST)


@dataclass(frozen=True)
class PublicListing:
    """A listing as the audience shows anyone (``GET /v1/public/listings``): plain text, ready for a template."""

    kind: str
    id: str
    path: str | None = None
    visibility: str | None = None
    title: str | None = None
    description: str | None = None
    address: str | None = None
    phone: str | None = None
    website: str | None = None
    listed: bool | None = None
    image: str | None = None
    start_at: datetime | None = None
    end_at: datetime | None = None
    venue_name: str | None = None
    ticket_url: str | None = None
    is_canceled: bool | None = None
    cover_cents: int | None = None
    raw: JSON = field(default_factory=dict, repr=False, compare=False)

    @property
    def is_public(self) -> bool:
        """Whether anyone may see it in full; "community" listings show in full only to members."""
        return self.visibility in (None, "public")

    @classmethod
    def from_json(cls, data: JSON) -> PublicListing:
        listed, canceled, cover = data.get("listed"), data.get("is_canceled"), data.get("cover_cents")
        return cls(
            kind=str(data.get("kind") or ""),
            id=str(data.get("id") or ""),
            path=_str(data.get("path")),
            visibility=_str(data.get("visibility")),
            title=_str(data.get("title")),
            description=_str(data.get("description")),
            address=_str(data.get("address")),
            phone=_str(data.get("phone")),
            website=_str(data.get("website")),
            listed=listed if isinstance(listed, bool) else None,
            image=_str(data.get("image")),
            start_at=parse_datetime(data.get("start_at")),
            end_at=parse_datetime(data.get("end_at")),
            venue_name=_str(data.get("venue_name")),
            ticket_url=_str(data.get("ticket_url")),
            is_canceled=canceled if isinstance(canceled, bool) else None,
            cover_cents=cover if isinstance(cover, int) else None,
            raw=data,
        )


@dataclass(frozen=True)
class PublicListingsPage:
    """One page of public listings: up to 500 venues, then events, then posts."""

    listings: list[PublicListing]
    page_count: int = 1
    next_page: int | None = None

    @classmethod
    def from_json(cls, data: Any) -> PublicListingsPage:
        body = data if isinstance(data, dict) else {}

        def number(value: Any) -> int | None:
            if isinstance(value, bool):
                return None
            if isinstance(value, int):
                return value
            return int(value) if isinstance(value, str) and value.isdigit() else None

        return cls(
            listings=[
                PublicListing.from_json(item) for item in _list(body.get("listings")) or [] if isinstance(item, dict)
            ],
            page_count=number(body.get("page_count")) or 1,
            next_page=number(body.get("next_page")),
        )


@dataclass(frozen=True)
class Community:
    """Everything the audience lists, read in one go (``community()``); a part whose module it lacks is empty."""

    audience: Audience | None
    locales: list[Locale]
    venues: list[Venue]
    people: list[Person]
    events: list[Event]
    event_series: list[EventSeries]
