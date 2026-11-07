"""AudienceKit SDK for Python: an audience's venues, people, locales and events over its GraphQL API.

from audiencekit import Client, Configuration, Credential

client = Client(Configuration(host="hotmess.social"))
client.adopt(Credential.from_json(saved))   # or client.sign_in_with_facebook(token, device)
for event in client.events():
    print(event.name, event.start_at, event.venue_name)
"""

from . import operations
from ._version import __version__
from .client import AsyncClient, Client
from .config import API_VERSION, CONSUMER_ENDPOINT, PRODUCTION_BASE_URL, Configuration, DeviceDescription
from .credential import Credential
from .errors import AudienceKitError, GraphQLError
from .models import (
    RSVP,
    AdmissionOffer,
    Audience,
    AudienceTheme,
    Branding,
    Coordinate,
    CoverCharge,
    Event,
    EventPerson,
    EventSeries,
    EventVenue,
    Friend,
    Locale,
    Location,
    Money,
    Node,
    Page,
    Person,
    PersonEvent,
    PersonEventInvolvement,
    PersonVenue,
    SelfUser,
    Tag,
    ThemeToken,
    TribeIdentification,
    Tribes,
    Troupe,
    Venue,
)
from .operations import Operation
from .schema import SchemaShape

__all__ = [
    "API_VERSION",
    "CONSUMER_ENDPOINT",
    "PRODUCTION_BASE_URL",
    "RSVP",
    "AdmissionOffer",
    "AsyncClient",
    "Audience",
    "AudienceKitError",
    "AudienceTheme",
    "Branding",
    "Client",
    "Configuration",
    "Coordinate",
    "CoverCharge",
    "Credential",
    "DeviceDescription",
    "Event",
    "EventPerson",
    "EventSeries",
    "EventVenue",
    "Friend",
    "GraphQLError",
    "Locale",
    "Location",
    "Money",
    "Node",
    "Operation",
    "Page",
    "Person",
    "PersonEvent",
    "PersonEventInvolvement",
    "PersonVenue",
    "SchemaShape",
    "SelfUser",
    "Tag",
    "ThemeToken",
    "TribeIdentification",
    "Tribes",
    "Troupe",
    "Venue",
    "__version__",
    "operations",
]
