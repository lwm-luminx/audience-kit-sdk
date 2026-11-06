package com.audiencekit

/**
 * Which fields an audience's schema has, as far as the SDK's documents need to know. The API leaves a module's
 * fields out of an audience that hasn't installed it (Facebook Pages, Google Places, RSVP, Ticketing, Friends…), and
 * asking for one fails the whole operation with `undefinedField`; the SDK builds its documents from this.
 *
 * [fields] is each type's fields by type; null assumes every field is there (before the SDK has had to ask).
 */
public class SchemaShape(private val fields: Map<String, Set<String>>?) {
    public fun has(type: String, field: String): Boolean = fields?.get(type)?.contains(field) ?: (fields == null)

    public companion object {
        /** Assumes every field is there: each operation's first try, so an audience with every module needs one call. */
        public val EVERYTHING: SchemaShape = SchemaShape(null)
    }
}
