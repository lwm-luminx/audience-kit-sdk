# Swift examples

Small pieces of an app built on the `AudienceKit` package, one per thing a screen does. They have no UI of their own,
so the same code feeds a SwiftUI view, a widget or a watch app, and the SDK's tests run every one against
`AudienceKitTesting`'s `GraphQLStub` (in `ExamplesTests.swift`), the stub your own app's tests can use too.

| File | What it shows |
| --- | --- |
| [`WhatsOn.swift`](../Tests/AudienceKitTests/Examples/WhatsOn.swift) | A locale's upcoming events grouped by night, in the locale's time zone, for a list or a widget |
| [`NewsDigest.swift`](../Tests/AudienceKitTests/Examples/NewsDigest.swift) | A Markdown digest of a locale's news and its national news |
| [`MemberActions.swift`](../Tests/AudienceKitTests/Examples/MemberActions.swift) | What a signed-in member does: RSVP, calendar links, the door pass (Apple platforms, which have CryptoKit) and reporting |

Signing in, the session and realtime are in the [package's README](../README.md).
