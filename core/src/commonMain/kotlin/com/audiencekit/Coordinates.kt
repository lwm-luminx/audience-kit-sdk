package com.audiencekit

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** A latitude and longitude in degrees. */
@Serializable
public data class Coordinate(val latitude: Double, val longitude: Double) {
    public companion object {
        /** Parses a WKT point, `POINT (<longitude> <latitude>)`, optionally with an SRID prefix. */
        public fun fromWkt(wkt: String): Coordinate? {
            val open = wkt.indexOf('(')
            val close = wkt.lastIndexOf(')')
            if (open < 0 || close < 0 || open >= close) return null
            if (!wkt.substring(0, open).uppercase().contains("POINT")) return null

            val numbers = wkt.substring(open + 1, close).trim().split(Regex("\\s+")).mapNotNull { it.toDoubleOrNull() }
            if (numbers.size < 2) return null
            return Coordinate(latitude = numbers[1], longitude = numbers[0])
        }
    }
}

/** A device's position, for the GraphQL `CoordinatesInput`. A beacon's major value names a locale. */
public data class Coordinates(
    val latitude: Double,
    val longitude: Double,
    val beaconMajor: Int? = null,
    val beaconMinor: Int? = null,
) {
    /** The value to pass as a `CoordinatesInput` variable. Zero beacon values mean no beacon. */
    public fun toGraphQLValue(): JsonElement = JsonObject(
        buildMap {
            put("latitude", JsonPrimitive(latitude))
            put("longitude", JsonPrimitive(longitude))
            beaconMajor?.takeIf { it != 0 }?.let { put("beaconMajor", JsonPrimitive(it)) }
            beaconMinor?.takeIf { it != 0 }?.let { put("beaconMinor", JsonPrimitive(it)) }
        },
    )
}
