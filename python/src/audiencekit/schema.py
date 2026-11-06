"""Which fields an audience's schema has, as far as the SDK's documents need to know."""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class SchemaShape:
    """Every type's fields, by type; ``None`` assumes every field is there (before the SDK has had to ask).

    The API leaves a module's fields out of an audience that hasn't installed it (Facebook Pages, Google Places, RSVP,
    Ticketing, Friends…), and asking for one fails the whole operation with ``undefinedField``; the SDK builds its
    documents from this.
    """

    fields: dict[str, frozenset[str]] | None = None

    def has(self, type_name: str, field: str) -> bool:
        if self.fields is None:
            return True
        return field in self.fields.get(type_name, frozenset())


EVERYTHING = SchemaShape(None)
"""Assumes every field is there: the first try of each operation, so an audience with every module needs one call."""
