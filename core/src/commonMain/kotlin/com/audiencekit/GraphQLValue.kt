package com.audiencekit

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Converts a Kotlin value to a GraphQL variable: `null`, booleans, numbers, strings, enums (by name),
 * lists, maps with string keys, and [JsonElement]s as they are.
 *
 * ```
 * client.graphQL<MyResult>(query, variables = graphQLVariables("id" to venueId, "limit" to 10))
 * ```
 */
public fun graphQLValueOf(value: Any?): JsonElement = when (value) {
    null -> JsonNull
    is JsonElement -> value
    is Boolean -> JsonPrimitive(value)
    is Number -> JsonPrimitive(value)
    is String -> JsonPrimitive(value)
    is Enum<*> -> JsonPrimitive(value.name)
    is Coordinates -> value.toGraphQLValue()
    is Iterable<*> -> JsonArray(value.map(::graphQLValueOf))
    is Array<*> -> JsonArray(value.map(::graphQLValueOf))
    is Map<*, *> -> JsonObject(value.entries.associate { (key, item) -> key.toString() to graphQLValueOf(item) })
    else -> throw IllegalArgumentException("${value::class.simpleName} can't be a GraphQL value")
}

/** A GraphQL `variables` object, converting each value with [graphQLValueOf]. */
public fun graphQLVariables(vararg pairs: Pair<String, Any?>): Map<String, JsonElement> =
    pairs.associate { (name, value) -> name to graphQLValueOf(value) }
