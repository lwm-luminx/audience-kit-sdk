import Foundation

/// Which of an audience's GraphQL endpoints a request goes to: its path segment under `/v1/audience/<id>/`. This SDK
/// is for the apps people use and speaks only to the consumer view (``consumer``), which grants a signed-in member
/// their own records and nothing more. Other views are named by the packages built for them (StaffKit adds its
/// staff endpoint), never here.
public struct GraphQLEndpoint: RawRepresentable, Hashable, Sendable {
    /// The path segment, `graphql` for the consumer view.
    public let rawValue: String
    /// Whether it's under `/v1/` itself, with no audience in its path: StaffKit's `/v1/staffql`, where Velvet and
    /// Backstage work on a listing of one's own in no audience or any number of them. Calls to it need no audience.
    public let isAudienceless: Bool

    public init(rawValue: String) {
        self.init(rawValue: rawValue, audienceless: false)
    }

    public init(rawValue: String, audienceless: Bool) {
        self.rawValue = rawValue
        self.isAudienceless = audienceless
    }

    /// `/v1/audience/<id>/graphql`, for the apps people use.
    public static let consumer = GraphQLEndpoint(rawValue: "graphql")

    /// The endpoint's path for an audience; an audience-less endpoint's ignores it.
    public func path(audienceID: String?) -> String {
        if isAudienceless { return "/v1/\(rawValue)" }
        return "/v1/audience/\(audienceID ?? "")/\(rawValue)"
    }
}
