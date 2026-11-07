import AudienceCore
import Foundation

/// What ``AudienceSession/reportContent(_:id:reason:block:)`` reports: the API's `ReportTarget`. Chat needs `message`
/// (a message's frame id) and `person` (a member's user id, as chat gives it).
public enum ReportTarget: String, Sendable, CaseIterable {
    case message = "MESSAGE"
    case person = "PERSON"
    case photo = "PHOTO"
    case ping = "PING"
    case post = "POST"
    case postComment = "POST_COMMENT"
    case venue = "VENUE"
}

/// What happened to a report: whether it was filed, and whether the person behind it is now blocked.
public struct ReportResult: Decodable, Sendable, Hashable {
    public let reported: Bool
    public let blocked: Bool

    public init(reported: Bool = false, blocked: Bool = false) {
        self.reported = reported
        self.blocked = blocked
    }
}

extension AudienceSession {
    /// Files a report with the audience's admins (App Store guideline 1.2, Google Play's user-generated content
    /// policy): `reportContent`. With `block`, the person behind it is blocked too, when there is one. `reason` is
    /// optional; offer ``ReportCopy/reasons``.
    @discardableResult
    public func reportContent(_ target: ReportTarget, id: String, reason: String? = nil,
                              block: Bool = false) async throws -> ReportResult {
        struct Response: Decodable, Sendable { let reportContent: ReportResult? }
        let query = """
            mutation ReportContent($targetType: ReportTarget!, $targetId: ID!, $reason: String, $block: Boolean) {
              reportContent(input: { targetType: $targetType, targetId: $targetId, reason: $reason, block: $block }) {
                reported
                blocked
              }
            }
            """
        return try await graphQL(query,
                                 variables: ["targetType": .string(target.rawValue), "targetId": .string(id),
                                             "reason": reason.map { .string($0) } ?? .null, "block": .bool(block)],
                                 operationName: "ReportContent", as: Response.self).reportContent ?? ReportResult()
    }

    /// Blocks a member (their user id): they and the signed-in person stop seeing each other's messages.
    public func blockUser(_ userID: String) async throws {
        struct Response: Decodable, Sendable {}
        _ = try await graphQL("mutation BlockUser($userId: ID!) { blockUser(input: { userId: $userId }) { blockedUsers { id } } }",
                              variables: ["userId": .string(userID)], operationName: "BlockUser", as: Response.self)
    }

    /// Unblocks a member blocked with ``blockUser(_:)`` or a report.
    public func unblockUser(_ userID: String) async throws {
        struct Response: Decodable, Sendable {}
        _ = try await graphQL("mutation UnblockUser($userId: ID!) { unblockUser(input: { userId: $userId }) { blockedUsers { id } } }",
                              variables: ["userId": .string(userID)], operationName: "UnblockUser", as: Response.self)
    }
}

/// The words around reporting and blocking, shared with Android so both apps say the same thing.
public enum ReportCopy {
    public static let reportMessage = "Report message"
    public static let blockPerson = "Block"
    public static let reportTitle = "Report this message?"
    public static let reportDetail = "The audience's admins will look at it. You can block the sender too, so you "
        + "stop seeing each other's messages."
    public static let alsoBlock = "Also block the sender"
    public static let blockTitle = "Block this person?"
    public static let blockDetail = "You'll stop seeing each other's messages. You can unblock them later."
    public static let reported = "Thanks. The admins will look at it."
    public static let blocked = "Blocked."
    public static let reasons = ["Spam", "Harassment or hate", "Sexual content", "Scam or fraud", "Other"]
}
