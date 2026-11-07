from __future__ import annotations

from audiencekit import SchemaShape, queries
from audiencekit.schema import EVERYTHING


def test_everything_asks_for_every_module_field() -> None:
    document = queries.venues(EVERYTHING)
    assert "profile { facebook { page" in document
    assert "places { placeId }" in document
    assert queries.people(EVERYTHING).count("involvements") == 1
    assert "rsvp { mine count }" in queries.events(EVERYTHING)
    assert "cover { charge" in queries.event(EVERYTHING)
    assert "venue { name venue" in queries.event_series(EVERYTHING)


def test_a_bare_schema_leaves_the_modules_out() -> None:
    bare = SchemaShape(
        {
            "Venue": frozenset({"id", "name"}),
            "Event": frozenset({"id"}),
            "Locale": frozenset({"id"}),
            "Person": frozenset({"id"}),
        }
    )
    assert "profile" not in queries.venues(bare)
    assert "places" not in queries.venues(bare)
    assert "venues { home" not in queries.people(bare)
    assert "involvements" not in queries.people(bare)
    events = queries.events(bare)
    assert "rsvp" not in events and "people {" not in events and "tickets" not in events and "venue {" not in events
    assert "venue {" not in queries.event_series(bare)
    assert "friends" not in queries.person_venue_fields(bare)
    assert "venue" not in queries.person_event_fields(bare)
    assert "cover" not in queries.event_tickets_fields(bare)
    assert "placeId" not in queries.closest_locale(bare)
    assert "placeId" not in queries.locales(bare)


def test_schema_shape_has() -> None:
    assert EVERYTHING.has("Anything", "atAll")
    shape = SchemaShape({"Venue": frozenset({"id"})})
    assert shape.has("Venue", "id")
    assert not shape.has("Venue", "profile")
    assert not shape.has("Locale", "id")


def test_schema_fields_document_aliases_each_type() -> None:
    document = queries.schema_fields(["Venue", "Locale"])
    assert 't0: __type(name: "Venue")' in document
    assert 't1: __type(name: "Locale")' in document
