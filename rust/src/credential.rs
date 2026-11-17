//! A session the API issued.

use std::fmt;

use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};

use crate::config::{API_VERSION, origin};

fn default_role() -> String {
    "member".to_string()
}

fn default_api_version() -> String {
    API_VERSION.to_string()
}

/// A session the API issued, as `POST /v1/token` (a person's) or `POST /v1/token/service` (a service token's) returns
/// it.
///
/// It says everything the client needs: which audience it is for, which GraphQL endpoint it was issued for (its
/// origin is the API instance to talk to), the role, and when it expires, if ever. Treat `token` like a password: the
/// `Debug` output leaves it out.
#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Credential {
    /// The bearer token.
    pub token: String,
    /// The person it is for; `None` for a service token's session.
    #[serde(default)]
    pub user_id: Option<String>,
    /// The audience it is for.
    #[serde(default)]
    pub audience_id: Option<String>,
    /// `member`, `admin`, `service`…
    #[serde(default = "default_role")]
    pub role: String,
    /// The GraphQL endpoint it was issued for.
    pub endpoint: String,
    /// The venue device it belongs to, if it is one's.
    #[serde(default)]
    pub venue_device_id: Option<String>,
    /// When it stops working, if ever.
    #[serde(default)]
    pub expires_at: Option<DateTime<Utc>>,
    /// The API contract it was issued under.
    #[serde(default = "default_api_version")]
    pub api_version: String,
    /// A service token's scopes, e.g. `public:read`.
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub scopes: Vec<String>,
    /// A service token's audience name.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub audience: Option<String>,
}

impl fmt::Debug for Credential {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Credential")
            .field("token", &"<redacted>")
            .field("user_id", &self.user_id)
            .field("audience_id", &self.audience_id)
            .field("role", &self.role)
            .field("endpoint", &self.endpoint)
            .field("expires_at", &self.expires_at)
            .field("scopes", &self.scopes)
            .finish_non_exhaustive()
    }
}

impl Credential {
    /// The API instance that issued the credential: its endpoint's origin.
    pub fn origin(&self) -> Option<String> {
        origin(&self.endpoint)
    }

    /// Whether it has expired, or will within `margin`.
    pub fn expires_within(&self, margin: Duration) -> bool {
        self.expires_at.is_some_and(|at| at - margin <= Utc::now())
    }

    /// Whether a service token's session carries `scope`.
    pub fn has_scope(&self, scope: &str) -> bool {
        self.scopes.iter().any(|held| held == scope)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn decodes_a_service_session_and_hides_its_token() {
        let credential: Credential = serde_json::from_value(json!({
            "token": "secret.jwt.value", "userId": null, "audienceId": "a-1", "role": "service",
            "endpoint": "https://api.audiencekit.com/v1/audience/a-1/graphql", "venueDeviceId": null,
            "expiresAt": "2099-01-01T00:00:00Z", "audience": "Hot Mess", "scopes": ["public:read"]
        }))
        .unwrap();
        assert_eq!(credential.role, "service");
        assert_eq!(credential.api_version, API_VERSION);
        assert!(credential.has_scope("public:read"));
        assert!(!credential.has_scope("diagnostics:read"));
        assert_eq!(credential.origin().as_deref(), Some("https://api.audiencekit.com"));
        assert!(!credential.expires_within(Duration::minutes(1)));
        let debug = format!("{credential:?}");
        assert!(!debug.contains("secret.jwt.value"), "{debug}");

        let round_trip: Credential = serde_json::from_value(serde_json::to_value(&credential).unwrap()).unwrap();
        assert_eq!(round_trip, credential);
    }

    #[test]
    fn defaults_and_expiry() {
        let mut credential: Credential =
            serde_json::from_value(json!({"token": "t", "endpoint": "https://x.test/v1/audience/a/graphql"})).unwrap();
        assert_eq!(credential.role, "member");
        assert!(!credential.expires_within(Duration::zero()));
        credential.expires_at = Some(Utc::now() + Duration::seconds(30));
        assert!(credential.expires_within(Duration::minutes(1)));
    }
}
