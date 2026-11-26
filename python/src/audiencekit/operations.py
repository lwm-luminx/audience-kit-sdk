"""The typed calls as data: a document, its variables, and how to read the answer. Both clients run them."""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass
from typing import Any, Generic, TypeVar

from . import queries
from .models import (
    JSON,
    RSVP,
    Admission,
    Article,
    ArticlesPage,
    Audience,
    CalendarFeed,
    ChatMessage,
    Coordinate,
    CoverPurchase,
    Event,
    EventSeries,
    Locale,
    Node,
    Person,
    Publication,
    ReportResult,
    SelfUser,
    Tag,
    TribeIdentification,
    Tribes,
    Venue,
    VenueCover,
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


def _compact(**values: Any) -> JSON | None:
    """``values`` without the ``None`` ones, for variables a document declares as optional."""
    kept = {key: value for key, value in values.items() if value is not None}
    return kept or None


def _at(data: Any, *path: str) -> Any:
    for key in path:
        data = data.get(key) if isinstance(data, dict) else None
    return data


# Members: RSVP, cover, chat


def cancel_rsvp(event_id: str) -> Operation[RSVP]:
    def decode(d: JSON) -> RSVP:
        rsvp = _at(d, "cancelRsvp", "event", "rsvp") or {}
        return RSVP(mine=str(rsvp.get("mine") or "UNSURE"), count=int(rsvp.get("count") or 0))

    return Operation("CancelRSVP", queries.CANCEL_RSVP, decode, variables={"eventId": event_id})


def venue_cover(venue_id: str) -> Operation[VenueCover | None]:
    def decode(d: JSON) -> VenueCover | None:
        venue = _at(d, "venues", "venue")
        return VenueCover.from_json(venue) if isinstance(venue, dict) else None

    return Operation(
        "VenueCover", queries.venue_cover, decode, variables={"id": venue_id}, types=queries.VENUE_TICKET_TYPES
    )


def admissions() -> Operation[list[Admission]]:
    return Operation(
        "Admissions",
        queries.ADMISSIONS,
        lambda d: [Admission.from_json(a) for a in _nodes(d, "me", "cover", "admissions", "nodes")],
    )


def buy_cover(venue_id: str, amount_cents: int | None = None, currency: str = "usd") -> Operation[CoverPurchase]:
    amount = None if amount_cents is None else {"cents": amount_cents, "currency": currency}
    return Operation(
        "BuyCover",
        queries.BUY_COVER,
        lambda d: CoverPurchase.from_json(_at(d, "buyCover") or {}),
        variables={"venueId": venue_id, "amount": amount},
    )


def buy_coat_check(venue_id: str, quantity: int = 1) -> Operation[CoverPurchase]:
    return Operation(
        "BuyCoatCheck",
        queries.BUY_COAT_CHECK,
        lambda d: CoverPurchase.from_json(_at(d, "buyCoatCheck") or {}),
        variables={"venueId": venue_id, "quantity": quantity},
    )


def _admission(field: str) -> Any:
    return lambda d: Admission.from_json(_at(d, field, "admission") or {"id": ""})


def pay_cover(admission_id: str, source_id: str, verification_token: str | None = None) -> Operation[Admission]:
    variables = {"admissionId": admission_id, "sourceId": source_id, "verificationToken": verification_token}
    return Operation("PayCover", queries.PAY_COVER, _admission("payCover"), variables=variables)


def confirm_cover(admission_id: str) -> Operation[Admission]:
    return Operation(
        "ConfirmCover", queries.CONFIRM_COVER, _admission("confirmCover"), variables={"admissionId": admission_id}
    )


def refund_admission(admission_id: str) -> Operation[Admission]:
    return Operation(
        "RefundAdmission",
        queries.REFUND_ADMISSION,
        _admission("refundAdmission"),
        variables={"admissionId": admission_id},
    )


def send_chat_message(
    text: str, venue_id: str | None = None, locale_id: str | None = None, prompt_id: str | None = None
) -> Operation[ChatMessage]:
    if (venue_id is None) == (locale_id is None):
        raise ValueError("A chat message goes to one room: a venue_id or a locale_id.")
    room: JSON = {"venueId": venue_id} if venue_id is not None else {"localeId": locale_id}
    chat_input: JSON = {**room, "message": text}
    if prompt_id is not None:
        chat_input["promptId"] = prompt_id
    return Operation(
        "SendMyChatMessage",
        queries.SEND_CHAT_MESSAGE,
        lambda d: ChatMessage.from_json(_at(d, "sendMyChatMessage", "message") or {"id": ""}),
        variables={"input": chat_input},
    )


def remove_chat_message(message_id: str) -> Operation[None]:
    return Operation(
        "RemoveMyChatMessage", queries.REMOVE_CHAT_MESSAGE, lambda d: None, variables={"messageId": message_id}
    )


# Soapbox (news)


def _articles(value: Any) -> list[Article]:
    return [Article.from_json(a) for a in value if isinstance(a, dict)] if isinstance(value, list) else []


def articles(
    locale_id: str | None = None, publication_id: str | None = None, first: int | None = None
) -> Operation[list[Article]]:
    return Operation(
        "Articles",
        queries.articles,
        lambda d: _articles(_at(d, "soapbox", "articles", "nodes")),
        variables=_compact(localeId=locale_id, publicationId=publication_id, first=first),
        types=queries.SOAPBOX_TYPES,
    )


def articles_page(
    locale_id: str | None = None, publication_id: str | None = None, first: int = 20, after: str | None = None
) -> Operation[ArticlesPage]:
    def decode(d: JSON) -> ArticlesPage:
        found = _at(d, "soapbox", "articles")
        connection: JSON = found if isinstance(found, dict) else {}
        page_info = connection.get("pageInfo")
        info: JSON = page_info if isinstance(page_info, dict) else {}
        return ArticlesPage(
            articles=_articles(connection.get("nodes")),
            end_cursor=info.get("endCursor"),
            has_next_page=bool(info.get("hasNextPage", False)),
        )

    return Operation(
        "ArticlesPage",
        queries.articles_page,
        decode,
        variables=_compact(localeId=locale_id, publicationId=publication_id, first=first, after=after),
        types=queries.SOAPBOX_TYPES,
    )


def national_articles(locale_id: str | None = None, first: int | None = None) -> Operation[list[Article]]:
    return Operation(
        "NationalArticles",
        queries.national_articles,
        lambda d: _articles(_at(d, "soapbox", "articles", "nodes")),
        variables=_compact(localeId=locale_id, first=first),
        types=queries.SOAPBOX_TYPES,
    )


def article(id: str) -> Operation[Article | None]:
    def decode(d: JSON) -> Article | None:
        found = _at(d, "soapbox", "article")
        return Article.from_json(found) if isinstance(found, dict) else None

    return Operation("Article", queries.article, decode, variables={"id": id}, types=queries.SOAPBOX_TYPES)


def articles_about(topic: str, id: str, first: int | None = None) -> Operation[list[Article]]:
    if topic not in queries.ARTICLE_TOPICS:
        raise ValueError(f"Articles are about a venue, event, person or locale, not {topic}.")

    def decode(d: JSON) -> list[Article]:
        listing = (
            _at(d, "venues", "venue") or _at(d, "events", "event") or _at(d, "people", "person") or d.get("locale")
        )
        return _articles(_at(listing, "articles", "list", "nodes"))

    return Operation(
        "ArticlesAbout",
        lambda shape: queries.articles_about(topic, shape),
        decode,
        variables=_compact(id=id, first=first),
        types=[*queries.SOAPBOX_TYPES, queries.ARTICLE_TOPICS[topic][0]],
    )


def publications() -> Operation[list[Publication]]:
    def decode(d: JSON) -> list[Publication]:
        found = _at(d, "soapbox", "publications")
        return [Publication.from_json(p) for p in found if isinstance(p, dict)] if isinstance(found, list) else []

    return Operation("Publications", queries.publications, decode, types=queries.SOAPBOX_TYPES)


def publication(id: str) -> Operation[Publication | None]:
    def decode(d: JSON) -> Publication | None:
        found = _at(d, "soapbox", "publication")
        return Publication.from_json(found) if isinstance(found, dict) else None

    return Operation("Publication", queries.publication, decode, variables={"id": id}, types=queries.SOAPBOX_TYPES)


def my_op_eds() -> Operation[list[Article]]:
    return Operation(
        "MyOpEds", queries.my_op_eds, lambda d: _articles(_at(d, "soapbox", "myOpEds")), types=queries.SOAPBOX_TYPES
    )


def submit_op_ed(
    publication_id: str, title: str, body: str, summary: str | None = None, byline: str | None = None
) -> Operation[Article]:
    variables = {"publicationId": publication_id, "title": title, "body": body, "summary": summary, "byline": byline}
    return Operation(
        "SubmitOpEd",
        queries.SUBMIT_OP_ED,
        lambda d: Article.from_json(_at(d, "submitOpEd", "article") or {"id": ""}),
        variables=variables,
    )


# Calendar subscription


def calendar_feed() -> Operation[CalendarFeed | None]:
    def decode(d: JSON) -> CalendarFeed | None:
        found = _at(d, "me", "calendarFeed")
        return CalendarFeed.from_json(found) if isinstance(found, dict) else None

    return Operation("CalendarFeed", queries.CALENDAR_FEED, decode)


def create_calendar_feed(reset: bool = False) -> Operation[CalendarFeed]:
    return Operation(
        "CreateCalendarFeed",
        queries.CREATE_CALENDAR_FEED,
        lambda d: CalendarFeed.from_json(_at(d, "createCalendarFeed", "calendarFeed") or {}),
        variables={"reset": reset},
    )


def follow_venue_in_calendar(venue_id: str, following: bool = True) -> Operation[CalendarFeed]:
    return Operation(
        "SetCalendarFeedVenue",
        queries.SET_CALENDAR_FEED_VENUE,
        lambda d: CalendarFeed.from_json(_at(d, "setCalendarFeedVenue", "calendarFeed") or {}),
        variables={"venueId": venue_id, "following": following},
    )


def delete_calendar_feed() -> Operation[bool]:
    return Operation(
        "DeleteCalendarFeed",
        queries.DELETE_CALENDAR_FEED,
        lambda d: _at(d, "deleteCalendarFeed", "deleted") is True,
    )


# Moderation and the account


def report_content(
    target_type: str, id: str, reason: str | None = None, block: bool = False
) -> Operation[ReportResult]:
    def decode(d: JSON) -> ReportResult:
        found = d.get("reportContent")
        result: JSON = found if isinstance(found, dict) else {}
        return ReportResult(reported=result.get("reported") is True, blocked=result.get("blocked") is True)

    return Operation(
        "ReportContent",
        queries.REPORT_CONTENT,
        decode,
        variables={"targetType": target_type, "targetId": id, "reason": reason, "block": block},
    )


def block_user(user_id: str) -> Operation[None]:
    return Operation("BlockUser", queries.BLOCK_USER, lambda d: None, variables={"userId": user_id})


def unblock_user(user_id: str) -> Operation[None]:
    return Operation("UnblockUser", queries.UNBLOCK_USER, lambda d: None, variables={"userId": user_id})


def delete_account() -> Operation[bool]:
    return Operation(
        "DeleteAccount",
        queries.DELETE_ACCOUNT,
        lambda d: _at(d, "deleteAccount", "deleted") is True,
        variables={"confirm": True},
    )
