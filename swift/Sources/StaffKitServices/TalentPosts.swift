import Foundation
import AudienceCore
import StaffKitCore

/// A talent listing's post: on their own page or on one of their events, shown as the listing. Hot Mess shows it on
/// their page, the event's page and the locale's updates.
public struct TalentPost: Decodable, Sendable, Identifiable, Hashable {
    public struct Photo: Decodable, Sendable, Hashable {
        public let url: String?
        public let altText: String?
    }
    /// The event it's on.
    public struct Event: Decodable, Sendable, Hashable {
        public let id: String
        public let name: String?
    }
    public let id: String
    public let body: String
    public let pinned: Bool
    public let commentsOpen: Bool
    public let commentCount: Int
    public let edited: Bool
    public let createdAt: String
    /// The part they have on the event ("MC", "Troupe", "Host"); nil on their own page.
    public let roleLabel: String?
    /// "Kiki Riot for House of Lux", on a troupe's post written by a member.
    public let actingPersonName: String?
    /// Whether the event's venue hid it from the event; it still shows on their page.
    public let hiddenFromEvent: Bool
    public let photos: [Photo]
    public let event: Event?
    public let viewerCanManage: Bool
}

/// Where a talent post goes: their own page, or one of their events.
public enum TalentPostTarget: Sendable, Hashable {
    case page
    case event(id: String)
}

/// A photo to post: an image URL or a data: URI, with the alt text Hot Mess reads out.
public struct TalentPostPhoto: Sendable, Hashable {
    public let photo: String
    public let altText: String
    public init(photo: String, altText: String) {
        self.photo = photo
        self.altText = altText
    }

    var input: GraphQLValue {
        var fields: [String: GraphQLValue] = ["photo": .string(photo)]
        let alt = altText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !alt.isEmpty { fields["altText"] = .string(alt) }
        return .object(fields)
    }
}

extension TalentManagementClient {
    /// The most photos one post holds.
    public static let maxPostPhotos = 4

    static let postFields = "id body pinned commentsOpen commentCount edited createdAt roleLabel actingPersonName hiddenFromEvent " +
        "photos { url altText } event { id name } viewerCanManage"

    /// The listing's posts, on its page and its events: pinned first, then newest.
    public func posts(personID: String, first: Int = 30) async throws -> [TalentPost] {
        struct Posts: Decodable, Sendable { let list: GraphQLNodes<TalentPost> }
        struct Person: Decodable, Sendable { let posts: Posts }
        struct People: Decodable, Sendable { let person: Person? }
        struct Response: Decodable, Sendable { let people: People }
        return try await session.graphQL("""
            query BackstagePosts($id: ID!, $first: Int!) {
              people { person(id: $id) { posts { list(first: $first) { nodes { \(Self.postFields) } } } } }
            }
            """, variables: ["id": .string(personID), "first": .int(first)], as: Response.self).people.person?.posts.list.nodes ?? []
    }

    /// Posts as the listing, on its page or an event it's on (from 30 days before until a day after). A troupe member
    /// posting for the troupe shows as "<member> for <troupe>".
    public func createPost(asPersonID personID: String, on target: TalentPostTarget, body: String,
                           photos: [TalentPostPhoto] = [], pinned: Bool = false, commentsOpen: Bool = true) async throws -> TalentPost {
        struct Payload: Decodable, Sendable { let post: TalentPost? }
        struct Response: Decodable, Sendable { let createPost: Payload }
        var input: [String: GraphQLValue] = [
            "asPersonId": .string(personID), "body": .string(body), "pinned": .bool(pinned), "commentsOpen": .bool(commentsOpen),
        ]
        switch target {
        case .page: input["personId"] = .string(personID)
        case let .event(id): input["eventId"] = .string(id)
        }
        if !photos.isEmpty { input["photos"] = .array(photos.prefix(Self.maxPostPhotos).map(\.input)) }
        let response = try await session.graphQL("""
            mutation BackstagePostCreate($input: PostCreateInput!) { createPost(input: $input) { post { \(Self.postFields) } } }
            """, variables: ["input": .object(input)], as: Response.self)
        guard let post = response.createPost.post else { throw AudienceKitError.decoding("The post was missing") }
        return post
    }

    /// Changes a post; nil leaves a field as it is.
    public func updatePost(id: String, body: String? = nil, pinned: Bool? = nil, commentsOpen: Bool? = nil) async throws -> TalentPost {
        struct Payload: Decodable, Sendable { let post: TalentPost? }
        struct Response: Decodable, Sendable { let updatePost: Payload }
        var input: [String: GraphQLValue] = ["id": .string(id)]
        if let body { input["body"] = .string(body) }
        if let pinned { input["pinned"] = .bool(pinned) }
        if let commentsOpen { input["commentsOpen"] = .bool(commentsOpen) }
        let response = try await session.graphQL("""
            mutation BackstagePostUpdate($input: PostUpdateInput!) { updatePost(input: $input) { post { \(Self.postFields) } } }
            """, variables: ["input": .object(input)], as: Response.self)
        guard let post = response.updatePost.post else { throw AudienceKitError.decoding("The post was missing") }
        return post
    }

    /// Takes a post and its comments out of the apps.
    public func deletePost(id: String) async throws {
        _ = try await session.graphQL("mutation BackstagePostDelete($input: PostDeleteInput!) { deletePost(input: $input) { post { id } } }",
                                      variables: ["input": .object(["id": .string(id)])], as: GraphQLValue.self)
    }
}
