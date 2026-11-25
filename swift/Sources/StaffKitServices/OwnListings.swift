import AudienceCore
import StaffKitCore

/// An audience a listing appears in (`audiences` on a person or venue). A listing started on its own in Backstage or
/// Velvet is in none until an audience lists it; one may be in any number.
public struct ListedAudience: Decodable, Sendable, Hashable, Identifiable {
    public let audienceId: String
    public let name: String
    public let subdomain: String
    public var id: String { audienceId }

    public init(audienceId: String, name: String, subdomain: String) {
        self.audienceId = audienceId; self.name = name; self.subdomain = subdomain
    }
}

/// What the signed-in person is to a listing (`viewerRole`).
public enum ListingRole: String, Decodable, Sendable, Hashable {
    /// Theirs: they started it, or accepted its owner invite.
    case owner = "OWNER"
    /// They manage it (an admin grant, or its Facebook Page is theirs).
    case manager = "MANAGER"
    /// They work at the venue.
    case staff = "STAFF"
    /// They act for this troupe as a member's manager.
    case troupe = "TROUPE"
    /// An admin of its audience or of AudienceKit.
    case admin = "ADMIN"
}

/// A talent listing the person manages anywhere, from the audience-less endpoint: the listing, the audiences it's in
/// and what they are to it.
public struct OwnListing: Decodable, Sendable, Identifiable {
    public let person: ManagedPerson
    /// The audiences that list it; empty for a listing of its own nobody lists yet.
    public let audiences: [ListedAudience]
    public let role: ListingRole?
    public var id: String { person.id }

    private enum CodingKeys: String, CodingKey { case audiences, viewerRole }

    public init(from decoder: any Decoder) throws {
        person = try ManagedPerson(from: decoder)
        let container = try decoder.container(keyedBy: CodingKeys.self)
        audiences = try container.decodeIfPresent([ListedAudience].self, forKey: .audiences) ?? []
        role = try? container.decodeIfPresent(ListingRole.self, forKey: .viewerRole)
    }
}

/// Backstage's single-user mode: listings of one's own, on `/v1/staffql` (``GraphQLEndpoint/audiencelessStaff``), with no
/// audience chosen. Needs ``AudienceManagementSession/canUseOwnListings``.
extension TalentManagementClient {
    /// A listing's own fields: no events, series or chat, which still need an audience.
    static let ownPersonFields = """
        id name avatarUrl profile { website socialLinks { nodes { id provider handle url } } }
        music { links { nodes { id provider handle url } } } tipping { options { provider handle url } }
        audiences { audienceId name subdomain } viewerRole
        """

    /// Every talent listing they manage, in any audience or none, and the troupes among them.
    public func ownListings() async throws -> (listings: [OwnListing], troupeIDs: Set<String>) {
        struct Response: Decodable, Sendable {
            struct Me: Decodable, Sendable { let listings: Listings }
            struct Listings: Decodable, Sendable { let people: [OwnListing]; let troupes: [GraphQLRef] }
            let me: Me
        }
        let response = try await session.ownListingsGraphQL(
            "# endpoint: audienceless\nquery BackstageOwnListings { me { listings { people { \(Self.ownPersonFields) } troupes { id } } } }",
            as: Response.self)
        return (response.me.listings.people, Set(response.me.listings.troupes.map(\.id)))
    }

    /// Starts a listing of their own, in no audience: theirs, whatever audiences list it later.
    public func createOwnPerson(name: String) async throws -> OwnListing {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let person: OwnListing }
            let createOwnPerson: Payload
        }
        return try await session.ownListingsGraphQL("""
            # endpoint: audienceless
            mutation BackstageCreateOwnPerson($input: OwnPersonCreateInput!) {
              createOwnPerson(input: $input) { person { \(Self.ownPersonFields) } }
            }
            """, variables: ["input": .object(["person": .object(["name": .string(name)])])],
            as: Response.self).createOwnPerson.person
    }

    /// ``updateProfile(id:name:website:socialLinks:)`` for a listing of their own, on the audience-less endpoint.
    public func updateOwnProfile(id: String, name: String, website: String? = nil,
                                 socialLinks: [SocialLinkInput]) async throws -> OwnListing {
        struct Response: Decodable, Sendable {
            struct Payload: Decodable, Sendable { let person: OwnListing }
            let updatePerson: Payload
        }
        var person: [String: GraphQLValue] = ["name": .string(name), "socialLinks": .array(socialLinks.map(\.graphQLValue))]
        if let website { person["website"] = .string(website) }
        return try await session.ownListingsGraphQL("""
            # endpoint: audienceless
            mutation BackstageOwnProfile($input: PersonUpdateInput!) {
              updatePerson(input: $input) { person { \(Self.ownPersonFields) } }
            }
            """, variables: ["input": .object(["id": .string(id), "person": .object(person)])],
            as: Response.self).updatePerson.person
    }
}
