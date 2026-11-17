//! Everything a client call can fail with.

use std::collections::BTreeMap;

use serde::{Deserialize, Serialize};
use serde_json::Value;

/// The codes an [`Error`] carries: the API's vocabulary (sent as `extensions.code` on GraphQL errors and as `error`
/// on REST ones) and the SDK's own.
pub mod codes {
    /// The credential is missing, invalid or ended.
    pub const UNAUTHENTICATED: &str = "UNAUTHENTICATED";
    /// The credential can't do this.
    pub const FORBIDDEN: &str = "FORBIDDEN";
    /// The record or audience doesn't exist (or isn't visible).
    pub const NOT_FOUND: &str = "NOT_FOUND";
    /// The input was refused; see [`Error::fields`](super::Error::fields).
    pub const INVALID: &str = "INVALID";
    /// Too many calls; try again later.
    pub const RATE_LIMITED: &str = "RATE_LIMITED";
    /// The change conflicts with another.
    pub const CONFLICT: &str = "CONFLICT";
    /// The API failed.
    pub const INTERNAL: &str = "INTERNAL";

    /// The client has no credential to send.
    pub const NOT_SIGNED_IN: &str = "NOT_SIGNED_IN";
    /// Any other unsuccessful HTTP status.
    pub const HTTP: &str = "HTTP";
    /// The request never got a response.
    pub const NETWORK: &str = "NETWORK";
    /// The response wasn't what the SDK expected.
    pub const DECODING: &str = "DECODING";
    /// A GraphQL error without a code.
    pub const GRAPHQL: &str = "GRAPHQL";
    /// The client doesn't know which audience to query.
    pub const MISSING_CONFIGURATION: &str = "MISSING_CONFIGURATION";
    /// The API no longer serves this SDK version.
    pub const UPDATE_REQUIRED: &str = "UPDATE_REQUIRED";
    /// The API no longer serves this SDK's API version.
    pub const UNSUPPORTED_API_VERSION: &str = "UNSUPPORTED_API_VERSION";
}

const UNSUPPORTED_API_VERSION_BODY: &str = "unsupported_api_version";

/// One entry of a GraphQL response's `errors` array.
#[derive(Clone, Debug, Default, PartialEq, Serialize, Deserialize)]
pub struct GraphQLError {
    /// What went wrong.
    #[serde(default)]
    pub message: String,
    /// Where in the response.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub path: Option<Vec<Value>>,
    /// The API's details, including `code`.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub extensions: Option<serde_json::Map<String, Value>>,
}

impl GraphQLError {
    /// `extensions.code`, when the API sent one.
    pub fn code(&self) -> Option<&str> {
        self.extensions.as_ref()?.get("code")?.as_str()
    }
}

/// A failed call: a [`code`](codes) from the API's vocabulary (or the SDK's own), a message, and what detail there
/// is. Small (one pointer), so results stay cheap to pass around.
#[derive(Debug)]
pub struct Error(Box<Details>);

impl std::fmt::Display for Error {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.write_str(&self.0.message)
    }
}

impl std::error::Error for Error {
    fn source(&self) -> Option<&(dyn std::error::Error + 'static)> {
        self.0.source.as_deref().map(|source| source as &(dyn std::error::Error + 'static))
    }
}

#[derive(Debug)]
struct Details {
    code: String,
    message: String,
    status: Option<u16>,
    fields: BTreeMap<String, Vec<String>>,
    errors: Vec<GraphQLError>,
    minimum_sdk_version: Option<String>,
    source: Option<Box<dyn std::error::Error + Send + Sync>>,
}

/// The result of a client call.
pub type Result<T, E = Error> = std::result::Result<T, E>;

impl Error {
    /// An error with a code and message and nothing else.
    pub fn new(code: impl Into<String>, message: impl Into<String>) -> Self {
        Error(Box::new(Details {
            code: code.into(),
            message: message.into(),
            status: None,
            fields: BTreeMap::new(),
            errors: Vec::new(),
            minimum_sdk_version: None,
            source: None,
        }))
    }

    fn with_status(mut self, status: u16) -> Self {
        self.0.status = Some(status);
        self
    }

    /// One of [`codes`], or another code the API sent.
    pub fn code(&self) -> &str {
        &self.0.code
    }

    /// A message that can be shown to a person.
    pub fn message(&self) -> &str {
        &self.0.message
    }

    /// The HTTP status, when there was a response.
    pub fn status(&self) -> Option<u16> {
        self.0.status
    }

    /// The API's per-field messages for [`codes::INVALID`] errors.
    pub fn fields(&self) -> &BTreeMap<String, Vec<String>> {
        &self.0.fields
    }

    /// The GraphQL response's errors, when the operation returned any.
    pub fn errors(&self) -> &[GraphQLError] {
        &self.0.errors
    }

    /// The oldest SDK the API still serves, for [`codes::UPDATE_REQUIRED`].
    pub fn minimum_sdk_version(&self) -> Option<&str> {
        self.0.minimum_sdk_version.as_deref()
    }

    /// Whether the credential was refused or is missing.
    pub fn is_unauthenticated(&self) -> bool {
        self.0.code == codes::UNAUTHENTICATED || self.0.code == codes::NOT_SIGNED_IN
    }

    /// The API refused the query because it asks for a field this audience's schema doesn't have.
    pub fn is_undefined_field(&self) -> bool {
        self.0.errors.iter().any(|error| error.code() == Some("undefinedField"))
    }

    pub(crate) fn not_signed_in() -> Self {
        Error::new(
            codes::NOT_SIGNED_IN,
            "The client has no credential. Give it a service token, an API key or a session.",
        )
    }

    pub(crate) fn unauthorized(message: Option<&str>) -> Self {
        Error::new(codes::UNAUTHENTICATED, message.unwrap_or("The credential was refused. Sign in again to continue."))
            .with_status(401)
    }

    pub(crate) fn network(error: reqwest::Error) -> Self {
        let mut value = Error::new(codes::NETWORK, format!("The API couldn't be reached: {error}"));
        value.0.source = Some(Box::new(error));
        value
    }

    pub(crate) fn decoding(detail: impl AsRef<str>) -> Self {
        Error::new(codes::DECODING, format!("The API sent a response the SDK didn't understand. {}", detail.as_ref()))
    }

    pub(crate) fn missing_configuration(detail: impl AsRef<str>) -> Self {
        Error::new(codes::MISSING_CONFIGURATION, format!("AudienceKit isn't configured: {}", detail.as_ref()))
    }

    /// The operation returned `errors`: the code and message are the first one's, and an `INVALID` error's
    /// `extensions.fields` become [`fields`](Error::fields).
    pub fn graphql(errors: Vec<GraphQLError>) -> Self {
        let first = errors.first();
        let code = first.and_then(GraphQLError::code).unwrap_or(codes::GRAPHQL).to_string();
        let message = first
            .map(|error| error.message.clone())
            .filter(|message| !message.is_empty())
            .unwrap_or_else(|| "The request failed.".to_string());
        let mut fields = BTreeMap::new();
        if let Some(Value::Object(sent)) = first.and_then(|error| error.extensions.as_ref()?.get("fields")) {
            for (name, value) in sent {
                let messages = match value {
                    Value::String(text) => vec![text.clone()],
                    Value::Array(items) => items.iter().filter_map(|item| item.as_str().map(String::from)).collect(),
                    _ => continue,
                };
                fields.insert(name.clone(), messages);
            }
        }
        let mut error = Error::new(code, message);
        error.0.fields = fields;
        error.0.errors = errors;
        error
    }

    /// The error for an unsuccessful REST status, reading `{"error": "<code>", "message": "…"}` when sent.
    pub fn for_status(status: u16, body: &Value) -> Self {
        let message =
            body.get("message").and_then(Value::as_str).or_else(|| body.get("fault")?.get("message")?.as_str());
        let sent_code = body.get("error").and_then(Value::as_str);
        match status {
            401 => return Error::unauthorized(message),
            403 => {
                return Error::new(codes::FORBIDDEN, message.unwrap_or("This credential doesn't have access to this."))
                    .with_status(403);
            }
            404 => return Error::new(codes::NOT_FOUND, message.unwrap_or("That isn't available.")).with_status(404),
            400 if sent_code == Some(UNSUPPORTED_API_VERSION_BODY) => {
                let mut text = message.unwrap_or("This version of the SDK is out of date.").to_string();
                if let Some(Value::Array(supported)) = body.get("supported") {
                    let versions: Vec<String> =
                        supported.iter().map(|v| v.as_str().map_or_else(|| v.to_string(), String::from)).collect();
                    if !versions.is_empty() {
                        text.push_str(&format!(" (API versions served: {}.)", versions.join(", ")));
                    }
                }
                return Error::new(codes::UNSUPPORTED_API_VERSION, text).with_status(400);
            }
            426 => {
                let mut error =
                    Error::new(codes::UPDATE_REQUIRED, message.unwrap_or("This version of the SDK is out of date."))
                        .with_status(426);
                error.0.minimum_sdk_version = body.get("minimum_sdk_version").and_then(Value::as_str).map(String::from);
                return error;
            }
            _ => {}
        }
        let code = match (sent_code, status) {
            (Some(code), _) => code.to_ascii_uppercase(),
            (None, 400 | 422) => codes::INVALID.to_string(),
            (None, 409) => codes::CONFLICT.to_string(),
            (None, 429) => codes::RATE_LIMITED.to_string(),
            (None, 500..) => codes::INTERNAL.to_string(),
            (None, _) => codes::HTTP.to_string(),
        };
        let message = message.map_or_else(|| format!("The API responded with status {status}."), String::from);
        Error::new(code, message).with_status(status)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn statuses() {
        assert_eq!(Error::for_status(401, &json!({})).code(), codes::UNAUTHENTICATED);
        let forbidden = Error::for_status(403, &json!({"message": "No"}));
        assert_eq!((forbidden.code(), forbidden.message()), (codes::FORBIDDEN, "No"));
        assert_eq!(Error::for_status(404, &json!(null)).code(), codes::NOT_FOUND);
        assert_eq!(Error::for_status(422, &json!({})).code(), codes::INVALID);
        assert_eq!(Error::for_status(409, &json!({})).code(), codes::CONFLICT);
        assert_eq!(Error::for_status(429, &json!({})).code(), codes::RATE_LIMITED);
        assert_eq!(Error::for_status(503, &json!({})).code(), codes::INTERNAL);
        assert_eq!(Error::for_status(418, &json!({})).code(), codes::HTTP);
        assert_eq!(Error::for_status(400, &json!({"error": "invalid"})).code(), codes::INVALID);
        let fault = Error::for_status(500, &json!({"fault": {"message": "boom"}}));
        assert_eq!(fault.message(), "boom");
        assert_eq!(fault.status(), Some(500));
    }

    #[test]
    fn version_errors() {
        let old = Error::for_status(
            400,
            &json!({"error": "unsupported_api_version", "message": "Too old.", "supported": ["2026-10-11", 2]}),
        );
        assert_eq!(old.code(), codes::UNSUPPORTED_API_VERSION);
        assert_eq!(old.message(), "Too old. (API versions served: 2026-10-11, 2.)");
        let update = Error::for_status(426, &json!({"minimum_sdk_version": "0.2.0"}));
        assert_eq!(update.code(), codes::UPDATE_REQUIRED);
        assert_eq!(update.minimum_sdk_version(), Some("0.2.0"));
    }

    #[test]
    fn graphql_errors() {
        let errors: Vec<GraphQLError> = serde_json::from_value(json!([
            {"message": "Bad", "extensions": {"code": "INVALID", "fields": {"name": ["is blank"], "age": "too low", "x": 1}}},
            {"message": "Field 'x' doesn't exist", "extensions": {"code": "undefinedField"}}
        ]))
        .unwrap();
        let error = Error::graphql(errors);
        assert_eq!(error.code(), codes::INVALID);
        assert_eq!(error.fields()["name"], vec!["is blank"]);
        assert_eq!(error.fields()["age"], vec!["too low"]);
        assert!(!error.fields().contains_key("x"));
        assert!(error.is_undefined_field());
        assert_eq!(error.to_string(), "Bad");

        let bare = Error::graphql(vec![GraphQLError::default()]);
        assert_eq!((bare.code(), bare.message()), (codes::GRAPHQL, "The request failed."));
        assert!(!bare.is_undefined_field());
        assert!(Error::not_signed_in().is_unauthenticated());
    }
}
