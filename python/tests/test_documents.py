"""Every document the SDK sends, built for an audience with every module, validates against the API's consumer schema
(``graphql/schema.graphql``), so a renamed or removed field fails here rather than in someone's app."""

from __future__ import annotations

from pathlib import Path

import pytest
from graphql import build_schema, parse, validate

from audiencekit import queries
from audiencekit.schema import EVERYTHING, SchemaShape

SCHEMA = build_schema((Path(__file__).parents[2] / "graphql" / "schema.graphql").read_text())

DOCUMENTS = {
    "audience": queries.AUDIENCE,
    "me": queries.ME,
    "node": queries.NODE,
    "tribes": queries.TRIBES,
    "identify_with_tribe": queries.IDENTIFY_WITH_TRIBE,
    "leave_tribe": queries.LEAVE_TRIBE,
    "rsvp_event": queries.RSVP_EVENT,
    "register_device": queries.REGISTER_DEVICE,
    "venues": queries.venues(EVERYTHING),
    "people": queries.people(EVERYTHING),
    "locales": queries.locales(EVERYTHING),
    "closest_locale": queries.closest_locale(EVERYTHING),
    "events": queries.events(EVERYTHING),
    "event": queries.event(EVERYTHING),
    "event_series": queries.event_series(EVERYTHING),
    "cancel_rsvp": queries.CANCEL_RSVP,
    "admissions": queries.ADMISSIONS,
    "venue_cover": queries.venue_cover(EVERYTHING),
    "buy_cover": queries.BUY_COVER,
    "buy_coat_check": queries.BUY_COAT_CHECK,
    "pay_cover": queries.PAY_COVER,
    "confirm_cover": queries.CONFIRM_COVER,
    "refund_admission": queries.REFUND_ADMISSION,
    "send_chat_message": queries.SEND_CHAT_MESSAGE,
    "remove_chat_message": queries.REMOVE_CHAT_MESSAGE,
    "articles": queries.articles(EVERYTHING),
    "articles_page": queries.articles_page(EVERYTHING),
    "national_articles": queries.national_articles(EVERYTHING),
    "article": queries.article(EVERYTHING),
    "publications": queries.publications(EVERYTHING),
    "publication": queries.publication(EVERYTHING),
    "my_op_eds": queries.my_op_eds(EVERYTHING),
    "submit_op_ed": queries.SUBMIT_OP_ED,
    "calendar_feed": queries.CALENDAR_FEED,
    "create_calendar_feed": queries.CREATE_CALENDAR_FEED,
    "set_calendar_feed_venue": queries.SET_CALENDAR_FEED_VENUE,
    "delete_calendar_feed": queries.DELETE_CALENDAR_FEED,
    "report_content": queries.REPORT_CONTENT,
    "block_user": queries.BLOCK_USER,
    "unblock_user": queries.UNBLOCK_USER,
    "delete_account": queries.DELETE_ACCOUNT,
    **{f"articles_about_{topic}": queries.articles_about(topic, EVERYTHING) for topic in queries.ARTICLE_TOPICS},
}


@pytest.mark.parametrize("name", sorted(DOCUMENTS))
def test_document_validates_against_the_consumer_schema(name: str) -> None:
    errors = validate(SCHEMA, parse(DOCUMENTS[name]))
    assert [error.message for error in errors] == []


def test_soapbox_documents_ask_for_nothing_without_soapbox() -> None:
    bare = SchemaShape({})
    for build in (
        queries.articles,
        queries.articles_page,
        queries.national_articles,
        queries.article,
        queries.publications,
        queries.publication,
        queries.my_op_eds,
    ):
        assert build(bare).endswith("{ id }")
    assert queries.articles_about("venue", bare) == "query ArticlesAbout { id }"
    assert "tickets" not in queries.venue_cover(bare)
    before_tips = SchemaShape({"Audience": frozenset({"soapbox"}), "Article": frozenset({"id"})})
    assert "viewerAdFree" not in queries.articles(before_tips)
    assert "adFreeOffered" not in queries.publication(before_tips)
    assert queries.national_articles(before_tips) == "query NationalArticles { id }"
    tips = SchemaShape(
        {
            "Audience": frozenset({"soapbox"}),
            "Article": frozenset({"viewerAdFree"}),
            "Publication": frozenset({"adFreeOffered"}),
        }
    )
    assert "adFreeOffered" in queries.articles(tips) and "viewerAdFree" in queries.articles(tips)
    assert "adFreeTipCents" in queries.publication(tips)
