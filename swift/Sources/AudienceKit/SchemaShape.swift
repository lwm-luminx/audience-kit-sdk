import AudienceCore
import Foundation

/// Which fields an audience's schema has, as far as the SDK's documents need to know. The API leaves a module's
/// fields out of an audience that hasn't installed it (Facebook Pages, Google Places, RSVP, Ticketing, Friends…), and
/// asking for one fails the whole operation with `undefinedField`; the SDK builds its documents from this.
struct SchemaShape: Sendable {
    /// Every type's fields, by type; nil assumes every field is there (before the SDK has had to ask).
    let fields: [String: Set<String>]?

    /// Assumes every field is there: the first try of each operation, so an audience with every module needs one call.
    static let everything = SchemaShape(fields: nil)

    func has(_ type: String, _ field: String) -> Bool {
        guard let fields else { return true }
        return fields[type]?.contains(field) ?? false
    }
}

extension AudienceSession {
    /// Runs the operation `document` builds, first for an audience with every module; when the API refuses a field
    /// (`undefinedField`), it asks the schema which fields `types` have and runs it again with only those. The answer
    /// is cached for the session, so later operations go straight to the right document.
    func graphQL<Response: Decodable & Sendable>(
        types: [String], variables: [String: GraphQLValue]? = nil, operationName: String,
        as type: Response.Type, document: (SchemaShape) -> String
    ) async throws -> Response {
        if let known = await cachedSchemaFields(of: types) {
            return try await graphQL(document(SchemaShape(fields: known)), variables: variables,
                                     operationName: operationName, as: type)
        }
        do {
            return try await graphQL(document(.everything), variables: variables, operationName: operationName,
                                     as: type)
        } catch let error as AudienceKitError where error.isUndefinedField {
            let shape = SchemaShape(fields: try await schemaFields(of: types))
            return try await graphQL(document(shape), variables: variables, operationName: operationName, as: type)
        }
    }
}

extension AudienceKitError {
    /// The API refused the query because it asks for a field this audience's schema doesn't have: one a module adds
    /// that the audience hasn't installed (or one from a newer API).
    var isUndefinedField: Bool { errors.contains { $0.code == "undefinedField" } }
}
