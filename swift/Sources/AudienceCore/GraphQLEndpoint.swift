import Foundation

/// Which of an audience's GraphQL endpoints a request goes to: its path segment under `/v1/audience/<id>/`. This SDK
/// is for the apps people use and speaks only to the consumer view (``consumer``), which grants a signed-in member
/// their own records and nothing more. Other views are named by the packages built for them (StaffKit adds its
/// staff endpoint), never here.
public struct GraphQLEndpoint: RawRepresentable, Hashable, Sendable {
    /// The path segment, `graphql` for the consumer view.
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// `/v1/audience/<id>/graphql`, for the apps people use.
    public static let consumer = GraphQLEndpoint(rawValue: "graphql")

    /// The endpoint's path for an audience.
    public func path(audienceID: String) -> String {
        "/v1/audience/\(audienceID)/\(rawValue)"
    }
}
