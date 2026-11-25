import Foundation

/// The API contract StaffKit speaks.
public enum StaffKitAPI {
    /// The date the API contract was last broken, sent on every call as `X-AudienceKit-API-Version`. The API refuses a
    /// version it doesn't serve with 400 `unsupported_api_version`, and echoes the version that answered.
    public static let version = "2026-10-11"
}
