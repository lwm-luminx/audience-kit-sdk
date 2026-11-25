import Foundation

/// A connection read as `nodes { … }`: the mixin lists (`events { upcoming }`, `venues { list }`) are connections
/// that return every item unless paged.
public struct GraphQLNodes<Item: Decodable & Sendable>: Decodable, Sendable {
    public let nodes: [Item]
    public init(nodes: [Item]) { self.nodes = nodes }
}

/// A record selected as `{ id }` only, to name it: the viewer's listings (`me { listings { venues { id } } }`).
public struct GraphQLRef: Decodable, Sendable, Hashable, Identifiable {
    public let id: String
    public init(id: String) { self.id = id }
}
