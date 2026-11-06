from __future__ import annotations

from audiencekit import AudienceKitError, GraphQLError
from audiencekit import errors as codes


def test_graphql_error_takes_the_first_errors_code_and_field_messages() -> None:
    errors = [
        GraphQLError.from_json(
            {
                "message": "Name can't be blank",
                "path": ["updateVenue"],
                "extensions": {"code": "INVALID", "fields": {"name": ["can't be blank"], "slug": "is taken"}},
            }
        ),
        GraphQLError.from_json({"message": "second"}),
    ]
    error = AudienceKitError.graphql(errors)
    assert error.code == codes.INVALID
    assert error.message == "Name can't be blank"
    assert error.fields == {"name": ["can't be blank"], "slug": ["is taken"]}
    assert error.errors == errors
    assert errors[0].code == "INVALID" and errors[1].code is None
    assert str(error) == "Name can't be blank"


def test_graphql_error_without_a_code_is_the_sdks_graphql_code() -> None:
    error = AudienceKitError.graphql([GraphQLError("Syntax error")])
    assert error.code == codes.GRAPHQL
    assert AudienceKitError.graphql([]).message == "The request failed."
    assert not error.is_undefined_field
    assert not error.is_unauthenticated


def test_undefined_field_is_recognised() -> None:
    error = AudienceKitError.graphql([GraphQLError("nope", extensions={"code": "undefinedField"})])
    assert error.is_undefined_field


def test_rest_statuses_map_to_codes() -> None:
    assert AudienceKitError.for_status(401, None).is_unauthenticated
    assert AudienceKitError.for_status(403, {"message": "Staff only"}).message == "Staff only"
    assert AudienceKitError.for_status(403, {}).code == codes.FORBIDDEN
    assert AudienceKitError.for_status(404, {}).code == codes.NOT_FOUND
    assert AudienceKitError.for_status(404, {"fault": {"message": "Gone"}}).message == "Gone"
    assert AudienceKitError.for_status(409, {}).code == codes.CONFLICT
    assert AudienceKitError.for_status(422, {}).code == codes.INVALID
    assert AudienceKitError.for_status(429, {}).code == codes.RATE_LIMITED
    assert AudienceKitError.for_status(500, {}).code == codes.INTERNAL
    assert AudienceKitError.for_status(418, "not json").code == codes.HTTP
    assert AudienceKitError.for_status(400, {"error": "bad_thing", "message": "Nope"}).code == "BAD_THING"


def test_unsupported_api_version_lists_the_served_versions() -> None:
    error = AudienceKitError.for_status(400, {"error": "unsupported_api_version", "supported": ["2026-10-11"]})
    assert error.code == codes.UNSUPPORTED_API_VERSION
    assert "2026-10-11" in error.message
    plain = AudienceKitError.for_status(400, {"error": "unsupported_api_version", "message": "Too old"})
    assert plain.message == "Too old"


def test_update_required_carries_the_minimum_version() -> None:
    error = AudienceKitError.for_status(426, {"minimum_sdk_version": "0.2.0"})
    assert error.code == codes.UPDATE_REQUIRED
    assert error.minimum_sdk_version == "0.2.0"
    assert error.status == 426
    assert AudienceKitError.for_status(426, {}).minimum_sdk_version == ""


def test_sdk_raised_values() -> None:
    assert AudienceKitError.not_signed_in().code == codes.NOT_SIGNED_IN
    assert AudienceKitError.sign_in_rejected().status == 401
    assert AudienceKitError.sign_in_failed(None).message == "Sign-in failed."
    assert AudienceKitError.network("boom").code == codes.NETWORK
    assert AudienceKitError.decoding("x").code == codes.DECODING
    assert AudienceKitError.missing_configuration("x").code == codes.MISSING_CONFIGURATION
    assert AudienceKitError.update_required("1.0.0", None).message.startswith("This version")
