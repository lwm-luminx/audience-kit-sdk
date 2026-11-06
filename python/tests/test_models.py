from __future__ import annotations

from datetime import datetime, timezone

from audiencekit import (
    Audience,
    Branding,
    Coordinate,
    Event,
    EventSeries,
    Locale,
    Person,
    SelfUser,
    Venue,
)
from audiencekit.models import parse_datetime


def test_parse_datetime() -> None:
    assert parse_datetime("2026-11-06T20:00:00Z") == datetime(2026, 11, 6, 20, tzinfo=timezone.utc)
    assert parse_datetime("2026-11-06T20:00:00") == datetime(2026, 11, 6, 20, tzinfo=timezone.utc)
    assert parse_datetime("2026-11-06T20:00:00-05:00").utcoffset() is not None
    assert parse_datetime(None) is None
    assert parse_datetime("") is None
    assert parse_datetime("not a date") is None
    assert parse_datetime(12) is None


def test_coordinate_from_wkt() -> None:
    point = Coordinate.from_wkt("POINT (-122.4194 37.7749)")
    assert point == Coordinate(latitude=37.7749, longitude=-122.4194)
    assert Coordinate.from_wkt("SRID=4326;POINT(-122.4 37.7)") == Coordinate(37.7, -122.4)
    assert point.wkt == "POINT (-122.4194 37.7749)"
    assert Coordinate.from_wkt("LINESTRING (0 0, 1 1)") is None
    assert Coordinate.from_wkt("POINT (37.7749 -122.4194)") is None  # swapped: not on Earth
    assert Coordinate.from_wkt("POINT (nan 1)") is None
    assert Coordinate.from_wkt("POINT (1)") is None
    assert Coordinate.from_wkt("POINT 1 2") is None
    assert Coordinate.from_wkt("POINT (x y)") is None
    assert Coordinate.from_wkt(None) is None


def test_coordinates_input_leaves_out_zero_beacons() -> None:
    point = Coordinate(1.5, 2.5)
    assert point.coordinates_input() == {"latitude": 1.5, "longitude": 2.5}
    assert point.coordinates_input(beacon_major=0, beacon_minor=0) == {"latitude": 1.5, "longitude": 2.5}
    assert point.coordinates_input(beacon_major=7, beacon_minor=3)["beaconMajor"] == 7
    assert point.coordinates_input(beacon_major=7, beacon_minor=3)["beaconMinor"] == 3


def test_venue_takes_its_name_from_its_page_when_it_has_none() -> None:
    venue = Venue.from_json(
        {
            "id": "v1",
            "name": None,
            "hidden": False,
            "order": 2,
            "profile": {"facebook": {"page": {"id": "p1", "name": "The Stud", "photoUrl": "x"}}},
            "locale": {"id": "l1", "name": "San Francisco", "profile": {"places": {"placeId": "ChIJ"}}},
            "location": {
                "id": "loc1",
                "point": "POINT (-122.4 37.7)",
                "address": "399 9th St",
                "places": {"placeId": "P"},
            },
            "tags": [{"id": "t1", "name": "Leather", "color": "#000"}],
        }
    )
    assert venue.name == "The Stud"
    assert venue.page is not None and venue.page.name == "The Stud"
    assert venue.locale is not None and venue.locale.google_place_id == "ChIJ"
    assert venue.location is not None and venue.location.coordinate == Coordinate(37.7, -122.4)
    assert venue.location.google_place_id == "P"
    assert venue.tags is not None and venue.tags[0].name == "Leather"
    assert venue.raw["order"] == 2


def test_venue_without_modules() -> None:
    venue = Venue.from_json({"id": "v2", "name": "Bar", "locale": {"id": "l1"}})
    assert venue.name == "Bar"
    assert venue.page is None and venue.location is None and venue.tags is None
    assert venue.locale == Locale(id="l1")
    assert Venue.from_json({"id": "v3"}).name == ""


def test_person_with_home_venue_and_events() -> None:
    person = Person.from_json(
        {
            "id": "p1",
            "name": "DJ Example",
            "order": 1,
            "global": True,
            "likeRequired": False,
            "venues": {
                "home": {
                    "id": "v1",
                    "name": "Home",
                    "locale": {"id": "l1"},
                    "friends": {"list": {"nodes": [{"id": "f1", "name": "Pat", "presence": "online"}]}},
                }
            },
            "locales": [{"id": "l1", "name": "SF"}],
            "events": {
                "involvements": {
                    "edges": [
                        {
                            "relationship": "PERFORMER",
                            "role": "DJ",
                            "via": {"id": "tr1", "name": "Troupe"},
                            "node": {
                                "id": "e1",
                                "name": "Night",
                                "startAt": "2026-11-07T04:00:00Z",
                                "venue": {"name": "Home", "venue": {"id": "v1", "name": "Home"}},
                            },
                        },
                        {
                            "relationship": "HOST",
                            "node": {"id": "e2", "venue": {"name": "To be announced", "venue": None}},
                        },
                        {"relationship": "BROKEN"},
                    ]
                }
            },
            "tags": [],
        }
    )
    assert person.name == "DJ Example" and person.global_
    assert person.home_venue is not None and person.home_venue.friends is not None
    assert person.home_venue.friends[0].presence == "online"
    assert person.locales == [Locale(id="l1", name="SF")]
    assert person.event_involvements is not None and len(person.event_involvements) == 2
    first = person.event_involvements[0]
    assert first.role == "DJ" and first.via is not None and first.via.name == "Troupe"
    assert first.event.venue is not None and first.event.venue.name == "Home"
    assert person.event_involvements[1].event.venue is None
    assert person.event_involvements[1].event.venue_name == "To be announced"
    assert person.events is not None and [e.id for e in person.events] == ["e1", "e2"]
    assert person.tags == []


def test_person_without_modules() -> None:
    person = Person.from_json({"id": "p2", "profile": {"facebook": {"page": {"id": "pg", "name": "Page Name"}}}})
    assert person.name == "Page Name"
    assert person.home_venue is None and person.locales is None and person.events is None


def test_event_with_every_module() -> None:
    event = Event.from_json(
        {
            "id": "e1",
            "name": "Big Night",
            "description": "desc",
            "startAt": "2026-11-07T04:00:00Z",
            "endAt": None,
            "isFeatured": True,
            "isCanceled": False,
            "locale": {"id": "l1"},
            "tags": [{"id": "t", "name": "Party"}],
            "venue": {
                "name": "The Stud",
                "venue": {"id": "v1", "name": "The Stud", "location": {"id": "loc", "point": "POINT (1 2)"}},
            },
            "rsvp": {"mine": "ATTENDING", "count": 12},
            "people": {"hosts": {"nodes": [{"id": "h1", "name": "Host"}]}, "lineup": {"nodes": []}},
            "tickets": {
                "url": "https://tickets.example",
                "offers": {
                    "nodes": [
                        {
                            "price": {"cents": 1500, "currency": "USD"},
                            "url": "https://x",
                            "seller": {"key": "eb", "name": "Eventbrite"},
                        },
                    ]
                },
                "cover": {
                    "charge": {
                        "amount": {"cents": 1000, "currency": "USD"},
                        "fee": {"cents": 100, "currency": "USD"},
                        "total": {"cents": 1100, "currency": "USD"},
                        "night": "2026-11-06",
                        "payable": True,
                        "event": {"id": "e1", "name": "Big Night"},
                    }
                },
            },
        }
    )
    assert event.start_at == datetime(2026, 11, 7, 4, tzinfo=timezone.utc)
    assert event.is_featured and not event.is_canceled
    assert event.venue is not None and event.venue.location is not None
    assert event.venue.location.coordinate == Coordinate(2, 1)
    assert event.rsvp is not None and event.rsvp.count == 12
    assert event.hosts is not None and event.hosts[0].name == "Host"
    assert event.lineup == []
    assert event.ticket_url == "https://tickets.example"
    assert event.ticket_offers is not None and event.ticket_offers[0].seller_name == "Eventbrite"
    assert event.ticket_offers[0].price is not None and event.ticket_offers[0].price.cents == 1500
    assert event.cover_charge is not None and event.cover_charge.total.cents == 1100
    assert event.cover_charge.event_name == "Big Night" and event.cover_charge.payable


def test_event_without_modules() -> None:
    event = Event.from_json({"id": "e2", "name": "Plain"})
    assert event.venue is None and event.venue_name is None and event.rsvp is None
    assert event.hosts is None and event.lineup is None
    assert event.ticket_url is None and event.ticket_offers is None and event.cover_charge is None
    assert event.locale is None and event.tags is None
    tickets_only = Event.from_json({"id": "e3", "tickets": {"url": None}})
    assert tickets_only.ticket_offers is None and tickets_only.cover_charge is None


def test_event_series() -> None:
    series = EventSeries.from_json(
        {
            "id": "s1",
            "name": "Weekly",
            "recurrenceText": "Every Friday",
            "startsOn": "2026-01-02",
            "startTime": "22:00",
            "timeZone": "America/Los_Angeles",
            "durationMinutes": 240,
            "venue": {"name": "The Stud", "venue": {"id": "v1"}},
        }
    )
    assert series.duration_minutes == 240
    assert series.venue is not None and series.venue.id == "v1"
    assert series.venue_name == "The Stud"
    assert EventSeries.from_json({"id": "s2"}).duration_minutes is None


def test_audience_theme_and_self_user() -> None:
    audience = Audience.from_json(
        {
            "id": "a",
            "name": "Hot Mess",
            "subdomain": "hotmess",
            "theme": {"preset": "neon", "tagline": "Hi", "light": [{"name": "bg", "value": "#fff"}], "dark": []},
        }
    )
    assert audience.theme is not None and audience.theme.light[0].value == "#fff"
    assert Audience.from_json({"id": "b"}).theme is None
    user = SelfUser.from_json({"id": "u", "name": "Pat Example", "isAdmin": True, "presence": "online"})
    assert user.is_admin and user.first_name is None


def test_branding_reads_both_shapes() -> None:
    nested = Branding.from_json(
        {"audience": {"id": "a1", "name": "Hot Mess"}, "facebook": {"appId": "123", "loginConfigId": "456"}}
    )
    assert nested.audience_id == "a1" and nested.facebook_app_id == "123"
    assert nested.facebook_login_config_id == "456" and nested.name == "Hot Mess"
    flat = Branding.from_json({"audienceId": "a2", "name": "X", "facebookAppId": "9"})
    assert flat.audience_id == "a2" and flat.facebook_app_id == "9" and flat.raw["name"] == "X"
