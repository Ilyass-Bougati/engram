# Engram for Android and iOS

A Flutter study companion for Engram: sign in, see what's due, study, and check your stats. Decks are managed in the web app.

See [docs/mobile.md](../docs/mobile.md) for what it covers, how it signs in, and how to run and build it.

| Path | What |
|---|---|
| `lib/api/` | The API client: bearer tokens, refresh-cookie replay, single-flight refresh |
| `lib/auth/` | The session state and the keystore-backed token store |
| `lib/screens/` | Server, sign-in, invite, decks, study, stats, settings |
| `lib/widgets/` | Card Markdown, glass, motion, loading/empty/error states |
| `lib/theme.dart` | The web app's design tokens |
| `test/` | Session logic, Markdown safety, collections, the study flow |
