//! Where the client talks to and which audience it speaks for.

use url::Url;

/// The hosted AudienceKit API.
pub const PRODUCTION_BASE_URL: &str = "https://api.audiencekit.com";

/// The API contract this SDK speaks, the date it was last broken: sent as [`API_VERSION_HEADER`].
pub const API_VERSION: &str = "2026-10-11";

/// The header that carries [`API_VERSION`].
pub const API_VERSION_HEADER: &str = "X-AudienceKit-API-Version";
/// The header that says a call comes from a staging build.
pub const ENVIRONMENT_HEADER: &str = "X-AudienceKit-Environment";
/// The header that names the client and its version (`AudienceKit-Rust/<version>`).
pub const CLIENT_HEADER: &str = "X-AudienceKit-Client";

/// The consumer view's path segment under `/v1/audience/<id>/`: the one for the apps people use.
pub const CONSUMER_ENDPOINT: &str = "graphql";

/// This crate's version, sent to the API in [`CLIENT_HEADER`].
pub const SDK_VERSION: &str = env!("CARGO_PKG_VERSION");

/// The GraphQL endpoint's path for an audience, e.g. `/v1/audience/<id>/graphql`.
pub fn endpoint_path(audience_id: &str, endpoint: &str) -> String {
    format!("/v1/audience/{audience_id}/{endpoint}")
}

/// Which of the audience's environments a build talks to.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub enum Environment {
    /// The audience's live apps.
    #[default]
    Production,
    /// Staging builds: they say so with [`ENVIRONMENT_HEADER`].
    Staging,
}

impl Environment {
    /// The value the API knows the environment by.
    pub fn as_str(self) -> &'static str {
        match self {
            Environment::Production => "production",
            Environment::Staging => "staging",
        }
    }
}

/// Where the client talks to and which audience it speaks for.
///
/// `base_url` is the API's base URL. `host` names the audience (e.g. `hotmess.social`): when no credential or
/// `audience_id` says which audience to query, the client asks `/v1/branding` for the one that owns it.
/// `audience_id` is the audience's UUID. `trusted_credential_origins` are other API instances whose credentials
/// `base_url` also accepts: a credential one of them issued is sent to `base_url` rather than its own instance.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Configuration {
    /// The API's base URL; [`PRODUCTION_BASE_URL`] by default.
    pub base_url: String,
    /// The audience's host, e.g. `hotmess.social`.
    pub host: Option<String>,
    /// The audience's UUID.
    pub audience_id: Option<String>,
    /// Production or staging.
    pub environment: Environment,
    /// Other API instances whose credentials `base_url` accepts.
    pub trusted_credential_origins: Vec<String>,
}

impl Default for Configuration {
    fn default() -> Self {
        Configuration {
            base_url: PRODUCTION_BASE_URL.to_string(),
            host: None,
            audience_id: None,
            environment: Environment::Production,
            trusted_credential_origins: Vec::new(),
        }
    }
}

impl Configuration {
    /// The API instance to send a credential to: the one that issued it, unless `base_url` trusts that one.
    pub fn api_base(&self, credential_endpoint: Option<&str>) -> String {
        let Some(issued_by) = credential_endpoint.and_then(origin) else {
            return self.base_url.clone();
        };
        if self.trusted_credential_origins.iter().any(|trusted| same_origin(trusted, &issued_by)) {
            self.base_url.clone()
        } else {
            issued_by
        }
    }
}

/// The origin of a URL, `scheme://host[:port]`, or `None` when it isn't one.
pub fn origin(url: &str) -> Option<String> {
    let parsed = Url::parse(url).ok()?;
    let host = parsed.host_str()?;
    Some(match parsed.port() {
        Some(port) => format!("{}://{}:{}", parsed.scheme(), host, port),
        None => format!("{}://{}", parsed.scheme(), host),
    })
}

/// Whether two URLs name the same API instance: scheme, host and port (the scheme's default when unsaid).
pub fn same_origin(a: &str, b: &str) -> bool {
    match (Url::parse(a), Url::parse(b)) {
        (Ok(left), Ok(right)) => {
            left.scheme().eq_ignore_ascii_case(right.scheme())
                && left.host_str().map(str::to_ascii_lowercase) == right.host_str().map(str::to_ascii_lowercase)
                && left.port_or_known_default() == right.port_or_known_default()
        }
        _ => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn endpoint_paths() {
        assert_eq!(endpoint_path("a-1", CONSUMER_ENDPOINT), "/v1/audience/a-1/graphql");
    }

    #[test]
    fn origins() {
        assert_eq!(
            origin("https://api.audiencekit.com/v1/audience/x/graphql").as_deref(),
            Some("https://api.audiencekit.com")
        );
        assert_eq!(origin("http://localhost:3000/v1").as_deref(), Some("http://localhost:3000"));
        assert_eq!(origin("not a url"), None);
        assert!(same_origin("https://API.audiencekit.com", "https://api.audiencekit.com:443/x"));
        assert!(!same_origin("https://api.audiencekit.com", "http://api.audiencekit.com"));
        assert!(!same_origin("nope", "https://api.audiencekit.com"));
    }

    #[test]
    fn api_base_follows_the_credential_unless_trusted() {
        let mut config = Configuration { base_url: "https://next.example".into(), ..Default::default() };
        assert_eq!(config.api_base(None), "https://next.example");
        assert_eq!(
            config.api_base(Some("https://api.audiencekit.com/v1/audience/a/graphql")),
            "https://api.audiencekit.com"
        );
        config.trusted_credential_origins.push("https://api.audiencekit.com".into());
        assert_eq!(config.api_base(Some("https://api.audiencekit.com/v1/audience/a/graphql")), "https://next.example");
        assert_eq!(config.api_base(Some("garbage")), "https://next.example");
    }

    #[test]
    fn environments() {
        assert_eq!(Environment::default().as_str(), "production");
        assert_eq!(Environment::Staging.as_str(), "staging");
    }
}
