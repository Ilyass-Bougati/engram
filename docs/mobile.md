# Mobile app

[`mobile/`](../mobile) is a Flutter app for Android and iOS. It is a study companion: you study on your phone, and manage decks in the browser.

| In the app | Web only |
|---|---|
| Sign in, and sign up from an invite link | Creating, editing and deleting decks and cards |
| Home: today's counts, the same "Suggested for you" deck as the web, what's up next, and a stats summary | Renaming, moving and deleting decks and collections |
| Your decks and collections, with today's due and new counts | Imports (deck files and Anki) and exports, forks |
| Studying a deck, or a whole collection | Sharing and members |
| Browsing a deck's cards: search, tag filter, each card read-only | Deck names and descriptions |
| Your new-card limit, per deck or for every deck in a collection | Admin: invites and accounts |
| Stats: streaks, activity, retention by month, card states | |
| Settings: theme, study reminders, timezone, password, server, sign out | |

It talks to the same API as the web app, and the backend needed no changes for it.

## Choosing a server

On first launch the app asks for the server's address, the one you open Engram at in a browser, such as `https://engram.example.com`. It checks `/api/health` before saving it. An address without a scheme gets `https://`.

To switch later, use **Switch server** in Settings, or on the sign-in screen. The picker lists every server used on the device, most recent first, and takes new addresses too.

- **Each server keeps its own sign-in.** Switching back to a server you're signed in to needs no password. Every server's refresh token is stored separately and only ever sent to the server that issued it.
- **Forgetting a server** (the bin icon) signs you out of it and takes it off the list. If it was the one in use, the app goes back to the picker.

Plain `http://` is refused, except for `localhost`, `127.x` and `10.0.2.2` (the Android emulator's address for the machine it runs on). That is for development only: Android release builds only allow https, and debug builds allow cleartext to those hosts and nothing else.

## Sessions

The app follows the same rules as the web client (see [security](security.md#sessions)):

- The **access token** is kept in memory only and sent as `Authorization: Bearer`. On a 401 the app refreshes once and retries.
- The **refresh token** is the `engram_refresh` cookie. The app reads it from `Set-Cookie` at sign-in, sign-up, refresh and password change, and sends it back as a `Cookie` header with `X-Engram-CSRF: 1`. Between launches it is kept in the OS keystore, one entry per server: the Keychain on iOS (this device only, after first unlock), and Keystore-backed storage on Android, with app backups and device transfer turned off.
- **Refreshes never overlap.** Each refresh rotates the token, and presenting a rotated one ends the whole sign-in as suspected theft. So concurrent requests that hit a 401 share one refresh.
- **Signing out** revokes the token chain on the server and deletes the stored token. Offline, the token is deleted on the phone anyway.

## Study reminders

Settings → Reminders turns on a daily nudge at up to four times you choose. Each reminder is skipped once the day's reviews are done. It all happens on the phone, with nothing new on the server:

- **Done means nothing left.** The app treats the day as done when every deck's due and new counts from `GET /api/decks` are zero. It checks whenever the deck list loads, when a study session ends, and when the app comes back to the foreground.
- **Skipping lasts until the study day ends.** That's 04:00 in your account's timezone, the same rollover as the server. If a session ended with cards coming back later the same day (learning steps), reminders resume from that time.
- **Reminder times follow the phone's clock.** That holds across daylight-saving changes and travel.
- **Reminders are scheduled two weeks ahead and redone every time the app learns something new.** A repeating notification can't skip a single day on iOS, so the app schedules one-off notifications instead. iOS keeps at most 64 pending, which is why there are at most four a day. If the app isn't opened for two weeks, reminders stop, and the last one says so.
- **The text is generic** ("Time to study"), not a count, because a count would be stale by the time it shows.
- **Permission is asked when you turn reminders on, not at launch.** If it's refused, the switch stays off and says where to turn notifications on.
- **Android timing is approximate.** Reminders may arrive a few minutes late, which needs no exact-alarm permission. They're put back after a reboot or an app update. Some phone makers' battery savers can still delay them.
- **Reminders belong to whoever is signed in on the server in use.** Signing out cancels them. Starting the app offline keeps the ones already scheduled.

## Card content

Cards go through one renderer, [`card_markdown.dart`](../mobile/lib/widgets/card_markdown.dart), with the same rules as the web app's:

- Raw HTML is dropped, not shown as text and never interpreted.
- Links open only for `http`, `https` and `mailto`, outside the app, in the browser or mail app. Other links do nothing.
- Images load from `https` only; anything else shows its alt text.
- Math (`$…$`, `$$…$$`) is typeset with KaTeX fonts. A formula that doesn't parse shows its source. Code blocks are highlighted.

## Design

The app is laid out for a phone. A glass bar along the bottom switches between four tabs:

- **Home**, the first page. It shows the suggestion, or "All done for today", plus today's counts, a stats strip (streak, reviews today, 30-day retention) and up to three more decks waiting.
- **Decks.** Top-level collections and loose decks. A collection opens its own page, with Study (the whole collection), New cards per day, and its decks and sub-collections. A deck opens its page: Study, its limit, and its cards to search and filter by tag.
- **Stats.**
- **Settings.**

Each tab keeps its own pages, so a deck left open in Decks is still there after a look at Stats. Tapping the tab you're on goes back to its first page, and Android's back button closes pages within a tab, then returns to Home. Studying opens full screen, above the tabs. Home, Decks and Stats share one copy of your decks and stats (`lib/library.dart`). It reloads after studying or changing a limit, and when the app comes back to the foreground.

The app uses the web app's design tokens, ported to [`theme.dart`](../mobile/lib/theme.dart): the same colors in light and dark, IBM Plex Sans and Mono (bundled, OFL), the same radii, and the same motion.

- **Glass** goes only on what floats over content, as on the web: the top bar and the bottom navigation bar (content scrolls under both), sheets, and the review card, which uses the thinner fill over the study backdrop. It is a 24 px blur with 140 % saturation, one edge and a highlight along the top. With the system's high-contrast setting on, glass turns into a solid surface.
- **The backdrop** is the web's paper gradient with a pine glow from the top left and a warm one from the bottom right. While studying, the pine glow moves behind the card.
- **The suggestion card** leads Home, as it leads the deck list on the web. It picks the same deck (`lib/suggestion.dart` ports `suggestion.ts`), over the same slow swirl of the three `suggestion` greens. The swirl is a fragment shader (`shaders/suggestion_swirl.frag`), the web's GLSL in Flutter's dialect. It holds still with reduced motion, and shows a solid green if the shader can't load.
- **Motion:** pages, new review cards and revealed answers rise in (fade plus 6 px, 200 ms); going back takes 120 ms. Menus grow from their corner, and sheets come in like the web's dialogs (280 ms). Everything uses the standard deceleration curve. With the system's reduce-motion setting on, nothing moves.

When a token changes in `frontend/src/styles/tokens.css`, change it in `theme.dart` too.

### App icon

The icon is the web app's mark ([`favicon.svg`](../frontend/public/favicon.svg)) on the paper color. It comes in three forms:

- **Android 8 and later:** an adaptive icon made of vectors, in `android/app/src/main/res/mipmap-anydpi-v26` and `drawable/ic_launcher_*.xml`. Launchers that follow dark mode show the favicon's dark colors. Android 13 themed icons use a one-color version.
- **iOS, and older Android:** PNGs drawn with the same painter as the in-app mark (`paintEngramMark`). After changing the mark, regenerate them and commit the result:

  ```bash
  flutter test tool/generate_icons_test.dart
  ```

  The vector icon has its own copy of the geometry, so change it there too.

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

An Android release build is signed with the key that `android/key.properties` points to (`storeFile`, `storePassword`, `keyAlias`, `keyPassword`). Without that file it falls back to the debug key, which is fine for trying a release build but not for sharing one. `key.properties` and keystores are gitignored. The app ID is `dev.engram.engram_mobile` on both platforms.

## Releases

[`.github/workflows/mobile.yml`](../.github/workflows/mobile.yml) runs the checks above on every pull request and push to `main` that touches `mobile/`. To publish a release, set `version` in `mobile/pubspec.yaml` (the part before `+`), commit, and push a matching tag:

```bash
git tag mobile-v0.2.0
git push origin mobile-v0.2.0
```

The workflow then:

1. Runs the checks.
2. Fails if the tag and the pubspec version disagree.
3. Builds the Android APK and App Bundle, signed with your upload key. The build number (Android's `versionCode`) is the workflow's run number, so each release installs over the last.
4. Publishes a GitHub release named after the tag with `engram-<version>.apk`, `engram-<version>.aab` and `SHA256SUMS`. People install the APK on their phones; the App Bundle is what Google Play takes, if you publish there.

iOS isn't built in CI. Build it on a Mac with `flutter build ipa`; shipping to iPhones needs an Apple developer account.

Mobile tags are separate from the server's `v*` tags, so the app and the server are released independently.

### The upload key

Android only installs an update signed with the same key as the installed app, so create one key and keep it. Losing it means everyone reinstalls.

```bash
keytool -genkeypair -v -keystore engram-upload.jks -storetype PKCS12 -keyalg RSA -keysize 2048 -validity 10000 -alias upload
```

Keep `engram-upload.jks` and its password somewhere safe, such as a password manager, outside the repository. Then add four repository secrets (Settings → Secrets and variables → Actions):

| Secret | Value |
|---|---|
| `ANDROID_KEYSTORE_BASE64` | the output of `base64 -w0 engram-upload.jks` |
| `ANDROID_KEYSTORE_PASSWORD` | the keystore password |
| `ANDROID_KEY_ALIAS` | `upload` |
| `ANDROID_KEY_PASSWORD` | the key password (the same as the keystore password for a PKCS12 keystore) |

Without them, the release job stops with an error instead of publishing a debug-signed build.

### When the API changes

The response shapes are written by hand in [`models.dart`](../mobile/lib/api/models.dart), like the web's `types.ts`. When a route the app uses changes, update them from [`openapi.json`](openapi.json).
