# Mobile app

[`mobile/`](../mobile) is a Flutter app for Android and iOS. It is a study companion: you study on your phone, and manage decks in the browser.

| In the app | Web only |
|---|---|
| Sign in, and sign up from an invite link | Creating, editing and deleting decks and cards |
| Your decks, grouped into collections, with today's due and new counts | Imports (deck files and Anki) and exports, forks |
| Studying basic and quiz cards | Sharing and members |
| Stats: streaks, retention, activity, card states | Deck settings, such as the new-card limit |
| Settings: theme, timezone, password, sign out | Admin: invites and accounts |

It talks to the same API as the web app, and the backend needed no changes for it.

## Connecting to a server

On first launch the app asks for the server's address, the one you open Engram at in a browser, such as `https://engram.example.com`. It checks `/api/health` before saving it. An address without a scheme gets `https://`.

Plain `http://` is refused, except for `localhost`, `127.x` and `10.0.2.2` (the Android emulator's address for the machine it runs on). That is for development only: Android release builds only allow https, and debug builds allow cleartext to those hosts and nothing else. Changing the server signs you out of the old one first, so a token is never sent to a different server.

## Sessions

The app follows the same rules as the web client (see [security](security.md#sessions)):

- The **access token** is kept in memory only and sent as `Authorization: Bearer`. On a 401 the app refreshes once and retries.
- The **refresh token** is the `engram_refresh` cookie. The app reads it from `Set-Cookie` at sign-in, sign-up, refresh and password change, and sends it back as a `Cookie` header with `X-Engram-CSRF: 1`. Between launches it is kept in the OS keystore: the Keychain on iOS (this device only, after first unlock), and Keystore-backed storage on Android, with app backups and device transfer turned off.
- **Refreshes never overlap.** Each refresh rotates the token, and presenting a rotated one ends the whole sign-in as suspected theft. So concurrent requests that hit a 401 share one refresh.
- **Signing out** revokes the token chain on the server and deletes the stored token. Offline, the token is deleted on the phone anyway.

## Card content

Cards go through one renderer, [`card_markdown.dart`](../mobile/lib/widgets/card_markdown.dart), with the same rules as the web app's:

- Raw HTML is dropped, not shown as text and never interpreted.
- Links open only for `http`, `https` and `mailto`, outside the app, in the browser or mail app. Other links do nothing.
- Images load from `https` only; anything else shows its alt text.
- Math (`$…$`, `$$…$$`) is typeset with KaTeX fonts. A formula that doesn't parse shows its source. Code blocks are highlighted.

## Design

The app uses the web app's design tokens, ported to [`theme.dart`](../mobile/lib/theme.dart): the same colors in light and dark, IBM Plex Sans and Mono (bundled, OFL), the same radii, and the same motion.

- **Glass** goes only on what floats over content, as on the web: the top bar (content scrolls under it), the account menu, sheets, and the review card, which uses the thinner fill over the study backdrop. It is a 24 px blur with 140 % saturation, one edge and a highlight along the top. With the system's high-contrast setting on, glass turns into a solid surface.
- **The backdrop** is the web's paper gradient with a pine glow from the top left and a warm one from the bottom right. While studying, the pine glow moves behind the card.
- **Motion:** pages, new review cards and revealed answers rise in (fade plus 6 px, 200 ms); going back takes 120 ms. Menus grow from their corner, and sheets come in like the web's dialogs (280 ms). Everything uses the standard deceleration curve. With the system's reduce-motion setting on, nothing moves.

When a token changes in `frontend/src/styles/tokens.css`, change it in `theme.dart` too.

## Development

Requirements: Flutter (stable), and the Android SDK or Xcode for running on a device.

```bash
cd mobile
flutter pub get
flutter analyze
dart format --output=none --set-exit-if-changed .
flutter test
```

The tests cover the session logic (cookie handling, single refresh, sign-out), the Markdown safety rules, the collection tree (the same cases as the web's), and the study flow.

To run against the Compose stack (see the [README](../README.md)) on an Android emulator, start the stack, run `flutter run`, and enter `http://10.0.2.2:6767` as the server. On the iOS simulator, use `http://127.0.0.1:6767`.

### Builds

```bash
flutter build apk --release      # Android
flutter build ipa                # iOS, on a Mac with Xcode and a signing team
```

The Android release build is signed with the debug key until a release keystore is configured in `android/app/build.gradle.kts`. The app ID is `dev.engram.engram_mobile` on both platforms.

### When the API changes

The response shapes are written by hand in [`models.dart`](../mobile/lib/api/models.dart), like the web's `types.ts`. When a route the app uses changes, update them from [`openapi.json`](openapi.json).
