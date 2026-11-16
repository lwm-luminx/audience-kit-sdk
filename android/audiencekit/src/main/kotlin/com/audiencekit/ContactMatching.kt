package com.audiencekit

import kotlinx.serialization.Serializable
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import java.io.File

// Friend matching from contacts (the API's doc/CONTACT_FRIEND_MATCHING.md). Someone proves their number with a text
// code, their phone sends one hash per contact (ContactHashing; names and numbers never leave the phone), and people
// who have each other saved are suggested to each other. Friends happen only through a request both agree to.
// The same as the Swift SDK's ContactMatching.swift.

/** Where the viewer stands with someone contact matching found. */
public enum class ContactMatchStatus {
    /** Nobody has asked yet: offer "Add". */
    NONE,

    /** The viewer asked; no answer yet (a quiet "Not now" also reads as this). */
    REQUESTED,

    /** They asked the viewer: offer "Accept" and "Not now". */
    INCOMING,

    /** Already friends. */
    FRIENDS,
}

/** Where a friend request stands, as the viewer sees it. */
public enum class FriendRequestStatus {
    PENDING,
    ACCEPTED,

    /** The person asked chose "Not now". Only they see this; the sender sees [PENDING]. */
    DISMISSED,

    /** The sender turned contact matching off before an answer. */
    WITHDRAWN,
}

/** A friend request between two people contact matching found. */
@Serializable
public data class FriendRequest(
    val id: String,
    val status: FriendRequestStatus,
    /** Who asked. */
    val user: Profile,
    /** Who was asked. */
    val friend: Profile,
    /** ISO 8601. */
    val createdAt: String? = null,
)

/** Someone on the app the viewer has saved in their contacts, who has the viewer's number saved too. */
@Serializable
public data class ContactMatch(
    /** Who they are: "First L." until friends. */
    val user: Profile,
    val status: ContactMatchStatus,
    /** The request between them while one is waiting for an answer, whichever of them sent it. */
    val request: FriendRequest? = null,
    /**
     * Which of the hashes just sent found them. Only on the answer to a check; [ContactMatchNames] remembers the
     * saved name it stands for.
     */
    val contactHash: String? = null,
)

/** The viewer's friend matching from contacts: `me.contactMatching`. Times are ISO 8601. */
@Serializable
public data class ContactMatching(
    /** Whether matching is on: they can find people and be found. Turns on with the first check after verifying. */
    val enabled: Boolean = false,
    /** Whether they proved their number by text. */
    val phoneVerified: Boolean = false,
    /** Their verified number in E.164. Only they ever see it. */
    val phoneNumber: String? = null,
    /** The name friends match them on. */
    val firstName: String? = null,
    val lastName: String? = null,
    /** When they may ask for another text code. */
    val codeResendAt: String? = null,
    val lastCheckedAt: String? = null,
    /** When they may check their contacts again (once a day). */
    val nextCheckAt: String? = null,
    /** How many contacts their last check covered. */
    val contactsChecked: Int = 0,
    /**
     * Whether a code can be texted right now. False until the platform has a text provider: hide the offer to turn
     * matching on. Null from an API older than the field, which is treated as available.
     */
    val textCodesAvailable: Boolean? = null,
    /** Everyone found both ways, with where they stand. Empty while matching is off. */
    val matches: List<ContactMatch> = emptyList(),
    /** Requests waiting on the viewer's answer, newest first. */
    val incomingRequests: List<FriendRequest> = emptyList(),
) {
    /** Whether to offer "Find friends from your contacts": not on yet, and a code could be texted. */
    val canOffer: Boolean get() = !enabled && textCodesAvailable != false

    /** The matches still showing "Add". */
    val addable: List<ContactMatch> get() = matches.filter { it.status == ContactMatchStatus.NONE }
}

/** The answer to a check: the state after it and everyone found, each with the hash that found them. */
public data class ContactCheckResult(val contactMatching: ContactMatching, val matches: List<ContactMatch>)

/** The API answered a contact matching call without its state: the audience doesn't have matching. */
public class ContactMatchingUnavailableException : Exception("Friend matching from contacts isn't available here.")

/** Where [ContactMatchNames] keeps its names: one small JSON document. */
public interface ContactMatchNameStore {
    public fun load(): String?
    public fun save(value: String?)
}

public class InMemoryContactMatchNameStore(private var value: String? = null) : ContactMatchNameStore {
    override fun load(): String? = value
    override fun save(value: String?) { this.value = value }
}

/** Keeps the names in [file] (on Android, under `context.noBackupFilesDir`, so they stay on the phone). */
public class FileContactMatchNameStore(private val file: File) : ContactMatchNameStore {
    override fun load(): String? = runCatching { file.readText() }.getOrNull()
    override fun save(value: String?) {
        if (value == null) file.delete() else runCatching { file.parentFile?.mkdirs(); file.writeText(value) }
    }
}

/**
 * The names the person saved their matches under, kept on the phone only and never sent, so a match can read
 * "In your contacts as Jordan Park". The API can't say: it never learns a name from anyone's contacts. Keep one
 * [store] per audience; [removeAll] when matching is turned off or on sign-out.
 */
public class ContactMatchNames(private val store: ContactMatchNameStore) {
    private val serializer = MapSerializer(String.serializer(), String.serializer())

    /** The name the person has [userId] saved under, when a check on this phone found them. */
    @Synchronized
    public fun name(userId: String): String? = all()[userId]

    /**
     * Remembers the saved name of everyone a check just found, from the [batch] that was sent. Names for people who
     * no longer match are dropped.
     */
    @Synchronized
    public fun record(matches: List<ContactMatch>, batch: ContactHashBatch) {
        val ids = matches.map { it.user.id }.toSet()
        val names = all().filterKeys { it in ids }.toMutableMap()
        for (match in matches) {
            val name = match.contactHash?.let { batch.names[it] } ?: continue
            names[match.user.id] = name
        }
        store.save(Json.encodeToString(serializer, names))
    }

    @Synchronized
    public fun removeAll() {
        store.save(null)
    }

    private fun all(): Map<String, String> =
        store.load()?.let { runCatching { Json.decodeFromString(serializer, it) }.getOrNull() } ?: emptyMap()
}

/**
 * The words the apps use for contact matching, so iOS and Android say the same thing. Never "upload", "sync" or
 * "hash" in front of people: a hash is a "scrambled code".
 */
public object ContactMatchingCopy {
    public const val TITLE: String = "Find friends from your contacts"
    public const val CARD_BODY: String =
        "Friends who turn this on too will show up here. We never keep your contacts or text anyone in them."
    public const val FIND_FRIENDS: String = "Find friends"
    public const val NOT_NOW: String = "Not now"
    public const val CHECKING: String = "Checking your contacts"
    public const val ONLY_CODES_LEAVE: String = "Only scrambled codes leave your phone."
    public const val NUMBER_PRIVATE: String =
        "Your number is never shown on your profile, and nobody can search for you by it."
    public const val RATES_MAY_APPLY: String = "Message and data rates may apply."
    public const val NO_FRIENDS_YET: String = "No friends here yet"
    public const val NO_FRIENDS_BODY: String =
        "None of the people in your contacts have turned this on yet. When someone who has your number does, " +
            "you'll both see each other."
    public const val NOT_NOW_IS_QUIET: String = "Not now hides it quietly. They aren't told."

    /** "4 friends are here" / "1 friend is here". */
    public fun friendsHere(count: Int): String = if (count == 1) "1 friend is here" else "$count friends are here"

    /** "Add 2 friends" / "Add 1 friend". */
    public fun addFriends(count: Int): String = if (count == 1) "Add 1 friend" else "Add $count friends"

    /** "In your contacts as Jordan Park". */
    public fun savedAs(name: String): String = "In your contacts as $name"

    /** "We checked 457 contacts and skipped 61 with only a first name." */
    public fun checked(batch: ContactHashBatch): String {
        val checked = "We checked ${batch.contactCount} ${if (batch.contactCount == 1) "contact" else "contacts"}"
        return if (batch.skippedWithoutFullName > 0) {
            "$checked and skipped ${batch.skippedWithoutFullName} with only a first name."
        } else {
            "$checked."
        }
    }
}

private val CONTACT_TYPES = listOf("ContactMatching", "ContactMatch")

/**
 * The signed-in person's contact matching: whether it's on, their number and match name, their matches and the
 * requests waiting on them.
 */
public suspend fun AudienceKitClient.contactMatching(): ContactMatching =
    graphQL(CONTACT_TYPES, ContactMatchingResponse.serializer(), null, "ContactMatching", ContactMatchingQueries::state)
        .me?.contactMatching ?: throw ContactMatchingUnavailableException()

/**
 * Saves the name friends match the person on and texts a six-digit code to [phoneNumber] (E.164, from
 * [ContactHashing.e164]). Up to five codes a day, 30 seconds apart.
 */
public suspend fun AudienceKitClient.startContactPhoneVerification(
    phoneNumber: String,
    firstName: String,
    lastName: String,
): ContactMatching = contactMutation(
    "StartContactPhoneVerification",
    graphQLVariables("phoneNumber" to phoneNumber, "firstName" to firstName, "lastName" to lastName),
    ContactMatchingQueries::start,
).state()

/** Proves the number with the code from the text. Matching is still off until the first check. */
public suspend fun AudienceKitClient.verifyContactPhone(code: String): ContactMatching =
    contactMutation("VerifyContactPhone", graphQLVariables("code" to code), ContactMatchingQueries::verify).state()

/**
 * Sends a batch of contact hashes ([ContactHashing.batch]), which turns matching on and replaces the last check.
 * Once a day. Pass [names] to remember, on the phone, what each match is saved as.
 */
public suspend fun AudienceKitClient.checkContacts(
    batch: ContactHashBatch,
    names: ContactMatchNames? = null,
): ContactCheckResult {
    val payload = contactMutation(
        "CheckContacts",
        graphQLVariables("hashes" to batch.hashes, "contactCount" to batch.contactCount),
        ContactMatchingQueries::check,
    )
    val matches = payload.matches.orEmpty()
    names?.record(matches, batch)
    return ContactCheckResult(payload.state(), matches)
}

/** Changes the name friends match the person on. */
public suspend fun AudienceKitClient.setContactMatchName(firstName: String, lastName: String): ContactMatching =
    contactMutation(
        "SetContactMatchName",
        graphQLVariables("firstName" to firstName, "lastName" to lastName),
        ContactMatchingQueries::setName,
    ).state()

/**
 * Turns matching off: the API deletes their number, match name and every code, and withdraws requests nobody
 * answered. Friends already made stay. Pass [names] to forget the saved names on the phone too.
 */
public suspend fun AudienceKitClient.disableContactMatching(names: ContactMatchNames? = null): ContactMatching {
    val state = contactMutation("DisableContactMatching", null, ContactMatchingQueries::disable).state()
    names?.removeAll()
    return state
}

/** Asks a match to be friends. If they had already asked, their request is accepted. */
public suspend fun AudienceKitClient.sendFriendRequest(userId: String): ContactMatching =
    contactMutation("SendFriendRequest", graphQLVariables("userId" to userId), ContactMatchingQueries::send).state()

/** Answers a request: accept it, or "Not now", which hides it without telling the sender. */
public suspend fun AudienceKitClient.respondToFriendRequest(id: String, accept: Boolean): ContactMatching =
    contactMutation(
        "RespondToFriendRequest",
        graphQLVariables("requestId" to id, "accept" to accept),
        ContactMatchingQueries::respond,
    ).state()

private suspend fun AudienceKitClient.contactMutation(
    operationName: String,
    variables: Map<String, kotlinx.serialization.json.JsonElement>?,
    document: (SchemaShape) -> String,
): ContactMatchingResponse.Payload {
    val response = graphQL(CONTACT_TYPES, ContactMatchingResponse.serializer(), variables, operationName, document)
    return response.payload?.takeIf { it.contactMatching != null } ?: throw ContactMatchingUnavailableException()
}

internal object ContactMatchingQueries {
    private const val REQUEST: String = "id status createdAt user { id name avatarUrl } friend { id name avatarUrl }"

    private fun match(shape: SchemaShape, checking: Boolean): String {
        val hash = if (checking && shape.has("ContactMatch", "contactHash")) "contactHash" else ""
        return "status $hash user { id name avatarUrl } request { $REQUEST }"
    }

    private fun fields(shape: SchemaShape): String {
        val available = if (shape.has("ContactMatching", "textCodesAvailable")) "textCodesAvailable" else ""
        return "enabled phoneVerified phoneNumber firstName lastName codeResendAt lastCheckedAt nextCheckAt " +
            "contactsChecked $available matches { ${match(shape, false)} } incomingRequests { $REQUEST }"
    }

    fun state(shape: SchemaShape): String = "query ContactMatching { me { contactMatching { ${fields(shape)} } } }"

    fun start(shape: SchemaShape): String = """
        mutation StartContactPhoneVerification(${'$'}phoneNumber: String!, ${'$'}firstName: String!, ${'$'}lastName: String!) {
          startContactPhoneVerification(input: { phoneNumber: ${'$'}phoneNumber, firstName: ${'$'}firstName, lastName: ${'$'}lastName }) {
            contactMatching { ${fields(shape)} }
          }
        }
    """.trimIndent()

    fun verify(shape: SchemaShape): String = """
        mutation VerifyContactPhone(${'$'}code: String!) {
          verifyContactPhone(input: { code: ${'$'}code }) { contactMatching { ${fields(shape)} } }
        }
    """.trimIndent()

    fun check(shape: SchemaShape): String = """
        mutation CheckContacts(${'$'}hashes: [String!]!, ${'$'}contactCount: Int!) {
          checkContacts(input: { hashes: ${'$'}hashes, contactCount: ${'$'}contactCount }) {
            matches { ${match(shape, true)} }
            contactMatching { ${fields(shape)} }
          }
        }
    """.trimIndent()

    fun setName(shape: SchemaShape): String = """
        mutation SetContactMatchName(${'$'}firstName: String!, ${'$'}lastName: String!) {
          setContactMatchName(input: { firstName: ${'$'}firstName, lastName: ${'$'}lastName }) {
            contactMatching { ${fields(shape)} }
          }
        }
    """.trimIndent()

    fun disable(shape: SchemaShape): String = """
        mutation DisableContactMatching {
          disableContactMatching(input: {}) { contactMatching { ${fields(shape)} } }
        }
    """.trimIndent()

    fun send(shape: SchemaShape): String = """
        mutation SendFriendRequest(${'$'}userId: ID!) {
          sendFriendRequest(input: { userId: ${'$'}userId }) { contactMatching { ${fields(shape)} } }
        }
    """.trimIndent()

    fun respond(shape: SchemaShape): String = """
        mutation RespondToFriendRequest(${'$'}requestId: ID!, ${'$'}accept: Boolean!) {
          respondToFriendRequest(input: { requestId: ${'$'}requestId, accept: ${'$'}accept }) {
            contactMatching { ${fields(shape)} }
          }
        }
    """.trimIndent()
}

@Serializable
internal data class ContactMatchingResponse(
    val me: Me? = null,
    val startContactPhoneVerification: Payload? = null,
    val verifyContactPhone: Payload? = null,
    val checkContacts: Payload? = null,
    val setContactMatchName: Payload? = null,
    val disableContactMatching: Payload? = null,
    val sendFriendRequest: Payload? = null,
    val respondToFriendRequest: Payload? = null,
) {
    @Serializable
    data class Me(val contactMatching: ContactMatching? = null)

    @Serializable
    data class Payload(val contactMatching: ContactMatching? = null, val matches: List<ContactMatch>? = null) {
        fun state(): ContactMatching = contactMatching ?: throw ContactMatchingUnavailableException()
    }

    val payload: Payload?
        get() = startContactPhoneVerification ?: verifyContactPhone ?: checkContacts ?: setContactMatchName
            ?: disableContactMatching ?: sendFriendRequest ?: respondToFriendRequest
}
