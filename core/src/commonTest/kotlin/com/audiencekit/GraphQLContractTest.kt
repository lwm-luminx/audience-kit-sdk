package com.audiencekit

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonPrimitive
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNull
import kotlin.test.assertSame

class GraphQLContractTest {
    private enum class State { MAYBE }

    @Test
    fun convertsNestedVariablesToTheWireFormat() {
        val variables = graphQLVariables(
            "input" to mapOf(
                "id" to "v-1", "enabled" to true, "limit" to 10,
                "ratio" to 0.5, "state" to State.MAYBE,
                "ids" to listOf("a", null), "tags" to arrayOf("b", "c"),
            ),
        )
        assertEquals(
            Json.parseToJsonElement("""{"id":"v-1","enabled":true,"limit":10,"ratio":0.5,"state":"MAYBE","ids":["a",null],"tags":["b","c"]}"""),
            variables["input"],
        )
    }

    @Test
    fun preservesJsonValuesAndNull() {
        val value = Json.parseToJsonElement("""{"nested":[1,null]}""")
        assertSame(value, graphQLValueOf(value))
        assertEquals(JsonNull, graphQLValueOf(null))
        assertEquals(emptyMap(), graphQLVariables())
    }

    @Test
    fun preservesExistingMapKeyAndDuplicateVariableBehavior() {
        assertEquals(Json.parseToJsonElement("""{"1":"one","null":false}"""), graphQLValueOf(mapOf(1 to "one", null to false)))
        assertEquals(mapOf("id" to JsonPrimitive("last")), graphQLVariables("id" to "first", "id" to "last"))
    }

    @Test
    fun rejectsUnsupportedValuesEvenInsideContainers() {
        assertFailsWith<IllegalArgumentException> { graphQLValueOf(Any()) }
        assertFailsWith<IllegalArgumentException> { graphQLValueOf(listOf(mapOf("bad" to Any()))) }
    }

    @Test
    fun omitsAbsentAndZeroBeaconsWithoutDroppingZeroCoordinates() {
        val expected = Json.parseToJsonElement("""{"latitude":0.0,"longitude":0.0}""")
        assertEquals(expected, graphQLValueOf(Coordinates(0.0, 0.0)))
        assertEquals(expected, graphQLValueOf(Coordinates(0.0, 0.0, 0, 0)))
        assertEquals(
            Json.parseToJsonElement("""{"latitude":37.77,"longitude":-122.42,"beaconMajor":12,"beaconMinor":3}"""),
            graphQLValueOf(Coordinates(37.77, -122.42, 12, 3)),
        )
    }

    @Test
    fun parsesLongitudeFirstWktAndSrid() {
        assertEquals(Coordinate(37.25, -122.5), Coordinate.fromWkt("POINT (-122.5 37.25)"))
        assertEquals(Coordinate(2.0, 1.0), Coordinate.fromWkt("SRID=4326;point(1\t2)"))
        for (invalid in listOf("", "POINT", "POINT ()", "POINT (1)", "POLYGON ((0 0, 1 1))")) {
            assertNull(Coordinate.fromWkt(invalid), invalid)
        }
    }

    @Test
    fun serializesCoordinateWithoutChangingFieldNames() {
        val coordinate = Coordinate(37.25, -122.5)
        val wire = """{"latitude":37.25,"longitude":-122.5}"""
        assertEquals(wire, Json.encodeToString(Coordinate.serializer(), coordinate))
        assertEquals(coordinate, Json.decodeFromString(Coordinate.serializer(), wire))
    }

    @Test
    fun routesEachEndpointBySegment() {
        assertEquals("/v1/audience/a-1/graphql", GraphQLEndpoint.CONSUMER.path("a-1"))
        assertEquals("/v1/audience/a-1/otherql", GraphQLEndpoint("otherql").path("a-1"))
        assertEquals(GraphQLEndpoint.CONSUMER, GraphQLEndpoint("graphql"))
    }
}
