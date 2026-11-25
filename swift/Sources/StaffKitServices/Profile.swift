import Foundation

/// Who someone is, as the signed-in user may see them (the API's `Profile`): the user's `id`, their `name` (in full
/// for themself, their friends and staff; "Aurora B." for anyone else) and their picture.
public struct Profile: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let avatarUrl: String?

    public init(id: String, name: String, avatarUrl: String? = nil) {
        self.id = id
        self.name = name
        self.avatarUrl = avatarUrl
    }
}
