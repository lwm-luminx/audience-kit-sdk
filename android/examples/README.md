# Kotlin examples

Small pieces of an app built on `com.audiencekit:audiencekit`, one per thing a screen does. They have no UI of their
own, so the same code feeds a Compose screen, a RecyclerView or a server, and the SDK's tests compile and run every
one against a stub API (`ExamplesTest`).

| File | What it shows |
| --- | --- |
| [`WhatsOn.kt`](WhatsOn.kt) | A locale's upcoming events grouped by night, in the locale's time zone, for a list or a widget |
| [`NewsDigest.kt`](NewsDigest.kt) | A Markdown digest of a locale's news and its national news |
| [`MemberActions.kt`](MemberActions.kt) | What a signed-in member does: RSVP, calendar links, the door pass and reporting |

Signing in, the session and the Android client are in the [SDK's README](../README.md).
