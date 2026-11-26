"""The whole community as JSON, for a static site generator (Pelican, MkDocs, Hugo) to build pages from.

AUDIENCEKIT_TOKEN=akst_… AUDIENCEKIT_HOST=hotmess.social python community_export.py > community.json
"""

from __future__ import annotations

import json
from typing import Any

from audiencekit import Client, Community


def accent(community: Community) -> str | None:
    """The audience's accent color, from its light theme."""
    theme = community.audience.theme if community.audience else None
    return next((token.value for token in theme.light if token.name == "accent"), None) if theme else None


def export_community(community: Community) -> dict[str, Any]:
    """The parts a site renders, flattened: venues with a map point, events with their venue's name, and the accent."""
    return {
        "audience": community.audience.name if community.audience else None,
        "accent": accent(community),
        "locales": [{"id": locale.id, "name": locale.name} for locale in community.locales],
        "venues": [
            {
                "id": venue.id,
                "name": venue.name,
                "locale": venue.locale.name if venue.locale else None,
                "point": (
                    {"latitude": point.latitude, "longitude": point.longitude}
                    if venue.location and (point := venue.location.coordinate)
                    else None
                ),
                "tags": [tag.name for tag in venue.tags or []],
            }
            for venue in community.venues
            if not venue.hidden
        ],
        "events": [
            {
                "id": event.id,
                "name": event.name,
                "start_at": event.start_at.isoformat() if event.start_at else None,
                "venue": event.venue_name,
            }
            for event in community.events
        ],
    }


if __name__ == "__main__":
    with Client.from_environment() as client:
        print(json.dumps(export_community(client.community()), indent=2))
