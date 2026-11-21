package com.audiencekit

import kotlinx.serialization.Serializable

// The Spotify bridge (audience_kit_api doc/SPOTIFY_BRIDGE.md): songs cross from a person's own Spotify to a venue as
// requests, and a venue's set list goes back out to people's own Spotify as a public playlist. Nobody signs in to
// Spotify for any of it, and Spotify only ever plays on the person's own account. Show Spotify's name and a link back
// with anything from Spotify, and never crop its artwork. The same as the Swift SDK's SpotifyBridge.swift.

/** A Spotify link someone shared or pasted, read without signing in to Spotify. */
@Serializable
public data class SpotifyLink(
    /** track, playlist, album or artist. */
    val kind: String,
    /** Spotify's ID for it. */
    val id: String,
    /** The song, playlist, album or artist name; null when Spotify didn't answer. */
    val title: String? = null,
    /** A song's artists, comma separated. */
    val artist: String? = null,
    val thumbnailUrl: String? = null,
    /** Its Spotify URI (`spotify:track:<id>`), which the Spotify app opens. */
    val uri: String,
    /** Its open.spotify.com link. */
    val url: String,
    /** Spotify's embed player, to show a playlist or album so the person can pick one song from it. */
    val embedUrl: String,
) {
    /** Whether it's one song, which can be asked for as a request. */
    val isSong: Boolean get() = kind == "track"

    public companion object {
        private val LINK = Regex(
            """(https?://(open\.spotify\.com|spotify\.link|spotify\.app\.link)/\S+|spotify:(track|playlist|album|artist):[A-Za-z0-9]+)""",
            RegexOption.IGNORE_CASE,
        )

        /** The first Spotify link in shared text, or null: a quick local check before asking the API. */
        public fun firstLink(text: String): String? = LINK.find(text)?.value
    }
}

/**
 * A night's set list on Spotify: a public playlist in the venue's account, for people to open in their own Spotify
 * (save it, add songs to their own playlists, or listen to rehearse). For personal listening only.
 */
@Serializable
public data class EventSetList(
    /** Its Spotify URI (`spotify:playlist:<id>`), which the Spotify app opens. */
    val spotifyUri: String,
    /** Its open.spotify.com link. */
    val spotifyUrl: String,
    val songCount: Int? = null,
    /** ISO 8601. */
    val syncedAt: String? = null,
)

/** A song request made from a Spotify link, as the queue shows it. */
@Serializable
public data class SpotifySongRequest(
    val id: String,
    val title: String,
    val artist: String? = null,
    val summary: String,
    val state: String,
    val position: Int = 0,
    val spotifyUri: String? = null,
)

/** What a shared or pasted Spotify link names; null when it isn't a Spotify link, or on an API before the bridge. */
public suspend fun AudienceKitClient.spotifyLink(url: String): SpotifyLink? = try {
    graphQL(SpotifyBridgeQueries.LINK, SpotifyLinkResponse.serializer(), graphQLVariables("url" to url), "SpotifyLink")
        .spotifyLink
} catch (error: AudienceKitException.GraphQL) {
    if (!error.isUndefinedField) throw error
    null
}

/**
 * Asks the venue to play a song shared from Spotify: the link fills in its name and artists, and the request keeps
 * the Spotify song. Only one song, not a playlist or album; the venue must be taking requests and the person must
 * be in its room, as for any request. [title] replaces Spotify's name when given.
 */
public suspend fun AudienceKitClient.requestSong(
    venueId: String,
    spotifyUrl: String,
    title: String? = null,
    note: String? = null,
): SpotifySongRequest {
    val pairs = listOfNotNull(
        "venueId" to venueId,
        "spotifyUrl" to spotifyUrl,
        title?.takeIf { it.isNotBlank() }?.let { "title" to it },
        note?.takeIf { it.isNotBlank() }?.let { "note" to it },
    )
    return graphQL(
        SpotifyBridgeQueries.REQUEST,
        SpotifyRequestResponse.serializer(),
        graphQLVariables(*pairs.toTypedArray()),
        "RequestSongFromSpotify",
    ).requestSong.request
}

/** An event's set list on Spotify, for a Listen in Spotify button; null until the venue mirrors it. */
public suspend fun AudienceKitClient.setList(eventId: String): EventSetList? = try {
    graphQL(SpotifyBridgeQueries.SET_LIST, EventSetListResponse.serializer(), graphQLVariables("id" to eventId),
        "EventSetList").events?.event?.setList
} catch (error: AudienceKitException.GraphQL) {
    if (!error.isUndefinedField) throw error
    null
}

internal object SpotifyBridgeQueries {
    val LINK: String = """
        query SpotifyLink(${'$'}url: String!) {
          spotifyLink(url: ${'$'}url) { kind id title artist thumbnailUrl uri url embedUrl }
        }
    """.trimIndent()

    val SET_LIST: String = """
        query EventSetList(${'$'}id: ID!) {
          events { event(id: ${'$'}id) { id setList { spotifyUri spotifyUrl songCount syncedAt } } }
        }
    """.trimIndent()

    val REQUEST: String = """
        mutation RequestSongFromSpotify(${'$'}venueId: ID!, ${'$'}spotifyUrl: String!, ${'$'}title: String, ${'$'}note: String) {
          requestSong(input: { venueId: ${'$'}venueId, kind: SONG, spotifyUrl: ${'$'}spotifyUrl, title: ${'$'}title, note: ${'$'}note }) {
            request { id title artist summary state position spotifyUri }
          }
        }
    """.trimIndent()
}

@Serializable
internal data class SpotifyLinkResponse(val spotifyLink: SpotifyLink? = null)

@Serializable
internal data class SpotifyRequestResponse(val requestSong: Payload) {
    @Serializable
    data class Payload(val request: SpotifySongRequest)
}

@Serializable
internal data class EventSetListResponse(val events: Mixin? = null) {
    @Serializable
    data class Event(val id: String, val setList: EventSetList? = null)

    @Serializable
    data class Mixin(val event: Event? = null)
}
