# Changelog

## 0.19.0 (2026-10-20)

- Sign in with Apple: `AppleWebSignIn` runs Apple's web sign-in in a Custom Tab (a Services ID, the API's
  `/v1/token/apple/callback` return URL and an `audiencekit-apple://callback` hand-back), and
  `signInWithApple(credential, signIn, device)` exchanges it at `POST /v1/token/apple` with the nonce that binds the
  token to the app.

## 0.18.0 (2026-10-18)

- `connectGoogle(idToken, device)` connects a Google account to the signed-in account (`POST /v1/token/google` with
  `connect`), whatever email either one has.
- `signInWithGoogle` takes an optional `accessToken` for the `user.emails.read` scope, so the API can match an existing
  account by the Google account's other verified emails, not only its primary one.

## 0.17.0 (2026-10-12)

The SDK's first release as its own repository; before this it lived in the AudienceKit monorepo at `sdk/kotlin`.

### Breaking

- The door calls for staff (`doorVenues()`, `venueDoor(venueId, night)`, `scanAdmission(venueId, code)`) and their
  models (`DoorVenue`, `DoorNight`, `DoorTickets`, `DoorCover`, `ScanResult`, `ScanOutcome`) moved to StaffKit for
  Android. Members' own passes (`admissions()`, `Admission.scanCount`, `checkedInAt`) stay here.
