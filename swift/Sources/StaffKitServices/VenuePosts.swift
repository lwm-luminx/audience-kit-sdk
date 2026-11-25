import Foundation
import AudienceCore

/// A venue's post on itself, one of its events or one of its series, shown as the venue.
public struct VenuePost: Decodable, Sendable, Identifiable {
    /// Someone's comment on it.
    public struct Comment: Decodable, Sendable, Identifiable, Hashable {
        public let id: String
        public let body: String
        public let createdAt: String
        /// As rooms show names, e.g. "Aurora B.".
        public let authorId: String
        public let authorName: String
        public let authorAvatarUrl: String?
        public let viewerCanRemove: Bool
    }
    /// The event or series it's on.
    public struct Subject: Decodable, Sendable, Hashable {
        public let id: String
        public let name: String?
    }
    public let id: String
    public let body: String
    public let photoUrl: String?
    public let pinned: Bool
    public let createdAt: String
    public let updatedAt: String
    public let event: Subject?
    public let eventSeries: Subject?
    public let viewerCanManage: Bool
    public let commentCount: Int
    /// Oldest first; at most the number asked for.
    public let comments: [Comment]

    private struct Comments: Decodable { let nodes: [Comment] }
    private enum CodingKeys: String, CodingKey {
        case id, body, photoUrl, pinned, createdAt, updatedAt, event, eventSeries, viewerCanManage, commentCount, comments
    }
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        body = try container.decode(String.self, forKey: .body)
        photoUrl = try container.decodeIfPresent(String.self, forKey: .photoUrl)
        pinned = try container.decode(Bool.self, forKey: .pinned)
        createdAt = try container.decode(String.self, forKey: .createdAt)
        updatedAt = try container.decode(String.self, forKey: .updatedAt)
        event = try container.decodeIfPresent(Subject.self, forKey: .event)
        eventSeries = try container.decodeIfPresent(Subject.self, forKey: .eventSeries)
        viewerCanManage = try container.decode(Bool.self, forKey: .viewerCanManage)
        commentCount = try container.decode(Int.self, forKey: .commentCount)
        comments = try container.decodeIfPresent(Comments.self, forKey: .comments)?.nodes ?? []
    }
}

/// What a post is on: the venue itself, one of its events, or one of its series.
public enum VenuePostTarget: Sendable, Hashable {
    case venue(id: String)
    case event(id: String)
    /// Series are found through the venue that owns them.
    case series(id: String, venueID: String)

    var inputField: (String, String) {
        switch self {
        case let .venue(id): ("venueId", id)
        case let .event(id): ("eventId", id)
        case let .series(id, _): ("eventSeriesId", id)
        }
    }
}

extension VenueManagementClient {
    /// A post's fields, with its first `comments` when that's more than zero. Lists leave comments out: every one counts
    /// toward the API's query complexity limit for every post.
    static func postFields(comments: Int) -> String {
        let fields = "id body photoUrl pinned createdAt updatedAt event { id name } eventSeries { id name } viewerCanManage commentCount"
        guard comments > 0 else { return fields }
        return fields + " comments(first: \(comments)) { nodes { id body createdAt authorId authorName authorAvatarUrl viewerCanRemove } }"
    }

    /// One post with its first `comments`, oldest first; nil once removed.
    public func post(id: String, comments: Int = 50) async throws -> VenuePost? {
        struct Posts: Decodable, Sendable { let post: VenuePost? }
        struct Response: Decodable, Sendable { let posts: Posts }
        return try await session.graphQL("query VelvetPost($id: ID!) { posts { post(id: $id) { \(Self.postFields(comments: comments)) } } }",
                                         variables: ["id": .string(id)], as: Response.self).posts.post
    }

    /// The posts on the venue, an event or a series: pinned first, then newest. `comments` is how many of each post's
    /// comments to include; none by default (see `post(id:comments:)`).
    public func posts(on target: VenuePostTarget, first: Int = 30, comments: Int = 0) async throws -> [VenuePost] {
        // The posts mixin's paged `list`.
        struct Posts: Decodable, Sendable { let list: GraphQLNodes<VenuePost> }
        struct Owner: Decodable, Sendable { let id: String?; let posts: Posts }
        let selection = "posts { list(first: \(first)) { nodes { \(Self.postFields(comments: comments)) } } }"
        switch target {
        case let .venue(id):
            struct Venues: Decodable, Sendable { let venue: Owner? }
            struct Response: Decodable, Sendable { let venues: Venues }
            return try await session.graphQL("query VelvetVenuePosts($id: ID!) { venues { venue(id: $id) { \(selection) } } }",
                                           variables: ["id": .string(id)], as: Response.self).venues.venue?.posts.list.nodes ?? []
        case let .event(id):
            struct Events: Decodable, Sendable { let event: Owner? }
            struct Response: Decodable, Sendable { let events: Events }
            return try await session.graphQL("query VelvetEventPosts($id: ID!) { events { event(id: $id) { \(selection) } } }",
                                           variables: ["id": .string(id)], as: Response.self).events.event?.posts.list.nodes ?? []
        case let .series(id, _):
            struct Events: Decodable, Sendable { let eventSeries: Owner? }
            struct Response: Decodable, Sendable { let events: Events }
            return try await session.graphQL("query VelvetSeriesPosts($id: ID!) { events { eventSeries(id: $id) { \(selection) } } }",
                                           variables: ["id": .string(id)], as: Response.self).events.eventSeries?.posts.list.nodes ?? []
        }
    }

    /// Posts as the venue. `photo` is an image URL or a data: URI.
    public func createPost(on target: VenuePostTarget, body: String, photo: String? = nil, pinned: Bool = false) async throws -> VenuePost {
        struct Payload: Decodable, Sendable { let post: VenuePost? }
        struct Response: Decodable, Sendable { let createPost: Payload }
        let (field, id) = target.inputField
        var input: [String: GraphQLValue] = ["body": .string(body), field: .string(id), "pinned": .bool(pinned)]
        if let photo { input["photo"] = .string(photo) }
        let response = try await session.graphQL("""
            mutation VelvetPostCreate($input: PostCreateInput!) { createPost(input: $input) { post { \(Self.postFields(comments: 50)) } } }
            """, variables: ["input": .object(input)], as: Response.self)
        guard let post = response.createPost.post else { throw AudienceKitError.decoding("The post was missing") }
        return post
    }

    /// Changes a post; nil leaves a field as it is. An empty `photo` removes it.
    public func updatePost(id: String, body: String? = nil, photo: String? = nil, pinned: Bool? = nil) async throws -> VenuePost {
        struct Payload: Decodable, Sendable { let post: VenuePost? }
        struct Response: Decodable, Sendable { let updatePost: Payload }
        var input: [String: GraphQLValue] = ["id": .string(id)]
        if let body { input["body"] = .string(body) }
        if let photo { input["photo"] = .string(photo) }
        if let pinned { input["pinned"] = .bool(pinned) }
        let response = try await session.graphQL("""
            mutation VelvetPostUpdate($input: PostUpdateInput!) { updatePost(input: $input) { post { \(Self.postFields(comments: 50)) } } }
            """, variables: ["input": .object(input)], as: Response.self)
        guard let post = response.updatePost.post else { throw AudienceKitError.decoding("The post was missing") }
        return post
    }

    /// Takes a post and its comments out of the apps.
    public func deletePost(id: String) async throws {
        _ = try await session.graphQL("mutation VelvetPostDelete($input: PostDeleteInput!) { deletePost(input: $input) { post { id } } }",
                                    variables: ["input": .object(["id": .string(id)])], as: GraphQLValue.self)
    }

    /// Removes a comment on one of the venue's posts.
    public func removePostComment(id: String) async throws {
        _ = try await session.graphQL("mutation VelvetCommentRemove($input: PostCommentRemoveInput!) { removePostComment(input: $input) { comment { id } } }",
                                    variables: ["input": .object(["id": .string(id)])], as: GraphQLValue.self)
    }
}
