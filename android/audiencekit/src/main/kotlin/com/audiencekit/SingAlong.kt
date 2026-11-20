package com.audiencekit

import kotlinx.serialization.Serializable
import java.text.Normalizer
import java.time.Instant

// Sing-along nights (audience_kit_api #760): a karaoke night whose provider is `sing_along`. There's no singer queue;
// the whole room sings along to the night's playlist (Spotify, shuffled by default) with the lyrics on the venue's
// screens. Velvet Display plays it and reports what's on and what's next (`Venue.music.nowPlaying`). Apps show the
// rotation (now playing, up next) and let people ask for a song from the playlist through the venue's song requests
// (`requestSong`). Lyrics are never shown in the apps: the licence covers the venue's screens only. The same as the
// Swift SDK's SingAlong.swift.

/** One song of a night's playlist. [uri] is its Spotify URI (`spotify:track:<id>`); [artist] is comma separated. */
@Serializable
public data class SingAlongTrack(
    val title: String,
    val artist: String? = null,
    val durationMs: Int? = null,
    val uri: String,
) {
    /**
     * Whether it's the song a request or a rotation entry names: the same title (and artist, when both have one),
     * ignoring case, accents and punctuation.
     */
    public fun matches(title: String, artist: String?): Boolean {
        if (SingAlongText.key(this.title) != SingAlongText.key(title)) return false
        val mine = this.artist?.let(SingAlongText::key) ?: return true
        val theirs = artist?.let(SingAlongText::key)?.takeIf { it.isNotEmpty() } ?: return true
        return mine.contains(theirs) || theirs.contains(mine)
    }

    /** Whether a search typed in the picker finds it: every word in the title or the artist. */
    public fun matches(search: String): Boolean {
        val words = SingAlongText.key(search).split(' ').filter { it.isNotEmpty() }
        if (words.isEmpty()) return true
        val haystack = SingAlongText.key("$title ${artist.orEmpty()}")
        return words.all { haystack.contains(it) }
    }
}

/**
 * A night's playlist. [url] is its web link; [uri] its Spotify URI (null for other links); [tracks] its songs in the
 * playlist's order, null when the API can't read Spotify's catalog for it.
 */
@Serializable
public data class SingAlongPlaylist(
    val provider: String = "spotify",
    val shuffle: Boolean = true,
    val url: String,
    val uri: String? = null,
    val tracks: List<SingAlongTrack>? = null,
) {
    /** The songs a search finds, in the playlist's order. */
    public fun tracks(matching: String): List<SingAlongTrack> = tracks.orEmpty().filter { it.matches(matching) }

    /** The playlist's song a request or rotation entry names, if it's on the playlist. */
    public fun track(title: String, artist: String?): SingAlongTrack? = tracks?.firstOrNull { it.matches(title, artist) }
}

/** A song the venue plays next. */
@Serializable
public data class UpNextSong(val title: String, val artist: String? = null)

/**
 * What the venue's player says is on (Velvet Display on a sing-along night), and what it plays next, in order.
 * [reportedAt] and [expiresAt] are ISO 8601; after [expiresAt] nothing is known to be playing.
 */
@Serializable
public data class NowPlaying(
    val title: String,
    val artist: String? = null,
    val album: String? = null,
    val artworkUrl: String? = null,
    val reportedAt: String? = null,
    val expiresAt: String? = null,
    val upNext: List<UpNextSong> = emptyList(),
) {
    /** Whether the report still holds at [now]. */
    public fun isFresh(now: Instant = Instant.now()): Boolean {
        val expires = expiresAt?.let { runCatching { Instant.parse(it) }.getOrNull() } ?: return true
        return expires.isAfter(now)
    }
}

/** Where a playlist song stands tonight, for the request picker. */
public enum class SingAlongTrackStatus { PLAYING_NOW, UP_NEXT, REQUESTED, IN_QUEUE }

/** A song already asked for tonight, as the picker compares it: a request still queued or up. */
public data class SingAlongAsk(val title: String, val artist: String? = null, val mine: Boolean = false)

/**
 * An event's sing-along: whether it is one ([isSingAlong]: its karaoke provider is `sing_along`), its playlist and its
 * venue's rotation right now ([nowPlaying], null when the player hasn't reported or the report went stale).
 */
public data class SingAlongNight(
    val eventId: String,
    val isSingAlong: Boolean,
    /** "Sing-along". */
    val providerName: String? = null,
    val playlist: SingAlongPlaylist? = null,
    val venueId: String? = null,
    val venueName: String? = null,
    val nowPlaying: NowPlaying? = null,
) {
    /**
     * Where [track] stands: playing now, up next, asked for by the signed-in user, or in the night's song queue. Null
     * when it can be asked for. Songs the shuffle already played aren't known, so they stay pickable. [asks] are
     * tonight's open song requests.
     */
    public fun status(track: SingAlongTrack, asks: List<SingAlongAsk> = emptyList()): SingAlongTrackStatus? {
        nowPlaying?.let { playing ->
            if (track.matches(playing.title, playing.artist)) return SingAlongTrackStatus.PLAYING_NOW
            if (playing.upNext.any { track.matches(it.title, it.artist) }) return SingAlongTrackStatus.UP_NEXT
        }
        val asked = asks.filter { track.matches(it.title, it.artist) }
        return when {
            asked.any { it.mine } -> SingAlongTrackStatus.REQUESTED
            asked.isNotEmpty() -> SingAlongTrackStatus.IN_QUEUE
            else -> null
        }
    }

    /** The playlist's songs a search finds, A to Z by title (a shuffled night has no order worth keeping). */
    public fun pickableTracks(matching: String = ""): List<SingAlongTrack> =
        playlist?.tracks(matching).orEmpty().sortedWith(compareBy(String.CASE_INSENSITIVE_ORDER) { it.title })
}

/** How sing-along compares song names: lowercased, without accents, apostrophes or punctuation. */
public object SingAlongText {
    private val MARKS = Regex("\\p{M}+")
    private val APOSTROPHES = Regex("['’]")
    private val NOT_KEPT = Regex("[^\\p{L}\\p{N}]+")

    public fun key(text: String): String = Normalizer.normalize(text, Normalizer.Form.NFKD).replace(MARKS, "")
        .lowercase().replace(APOSTROPHES, "").replace(NOT_KEPT, " ").trim()
}

/**
 * An event's sing-along: whether it is one, its playlist and its venue's rotation. Null for an unknown event. On an
 * API without sing-along it reads as not a sing-along.
 */
public suspend fun AudienceKitClient.singAlong(eventId: String, now: Instant = Instant.now()): SingAlongNight? = graphQL(
    SingAlongQueries.TYPES,
    SingAlongResponse.serializer(),
    graphQLVariables("id" to eventId),
    "SingAlong",
    SingAlongQueries::singAlong,
).night(now)

/**
 * A venue's rotation right now, for refreshing a sing-along card while it's on screen: null when its player hasn't
 * reported or the report went stale.
 */
public suspend fun AudienceKitClient.nowPlaying(venueId: String, now: Instant = Instant.now()): NowPlaying? = graphQL(
    SingAlongQueries.TYPES,
    NowPlayingResponse.serializer(),
    graphQLVariables("id" to venueId),
    "NowPlaying",
    SingAlongQueries::nowPlaying,
).node?.music?.nowPlaying?.takeIf { it.isFresh(now) }

internal object SingAlongQueries {
    val TYPES: List<String> = listOf("Event", "IKaraokeNight", "Venue", "IVenueMusic", "EquipmentTrack")

    private const val NOW_PLAYING_FIELDS = "title artist album artworkUrl reportedAt expiresAt upNext { title artist }"

    fun singAlong(shape: SchemaShape): String {
        val karaoke = if (shape.has("IKaraokeNight", "singAlong")) " karaoke { singAlong providerName }" else ""
        val playlist = if (shape.has("Event", "playlist")) {
            " playlist { provider shuffle url uri tracks { title artist durationMs uri } }"
        } else {
            ""
        }
        val music = if (shape.has("IVenueMusic", "nowPlaying")) " music { nowPlaying { $NOW_PLAYING_FIELDS } }" else ""
        return """
            query SingAlong(${'$'}id: ID!) {
              events { event(id: ${'$'}id) { id$karaoke$playlist venue { venue { id name$music } } } }
            }
        """.trimIndent()
    }

    fun nowPlaying(shape: SchemaShape): String {
        if (!shape.has("IVenueMusic", "nowPlaying")) return "query NowPlaying(${'$'}id: ID!) { node(id: ${'$'}id) { id } }"
        return """
            query NowPlaying(${'$'}id: ID!) {
              node(id: ${'$'}id) { ... on Venue { music { nowPlaying { $NOW_PLAYING_FIELDS } } } }
            }
        """.trimIndent()
    }
}

@Serializable
internal data class SingAlongResponse(val events: Mixin? = null) {
    @Serializable
    data class Karaoke(val singAlong: Boolean? = null, val providerName: String? = null)

    @Serializable
    data class Music(val nowPlaying: NowPlaying? = null)

    @Serializable
    data class Venue(val id: String, val name: String? = null, val music: Music? = null)

    @Serializable
    data class Where(val venue: Venue? = null)

    @Serializable
    data class Event(
        val id: String,
        val karaoke: Karaoke? = null,
        val playlist: SingAlongPlaylist? = null,
        val venue: Where? = null,
    )

    @Serializable
    data class Mixin(val event: Event? = null)

    fun night(now: Instant): SingAlongNight? {
        val event = events?.event ?: return null
        val venue = event.venue?.venue
        return SingAlongNight(
            eventId = event.id,
            isSingAlong = event.karaoke?.singAlong ?: false,
            providerName = event.karaoke?.providerName,
            playlist = event.playlist,
            venueId = venue?.id,
            venueName = venue?.name,
            nowPlaying = venue?.music?.nowPlaying?.takeIf { it.isFresh(now) },
        )
    }
}

@Serializable
internal data class NowPlayingResponse(val node: Venue? = null) {
    @Serializable
    data class Venue(val music: SingAlongResponse.Music? = null)
}
