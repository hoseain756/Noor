# Noor for mobile

Native Flutter client for Android phones, iPhones, and tablets. **Fully
account-free**: every provider is called directly from the device and there is
no server dependency of any kind.

## Highlights

- **No login, ever.** No account, no pairing, no server. Install and watch.
- **Built-in torrent engine** (libtorrent via jlibtorrent, prebuilt natives —
  no NDK needed): paste a **magnet link or info hash** in *Library → Torrent*
  and stream directly, or tap a `magnet:` link in any browser app to open Noor.
  Sequential downloading with first/last-piece priority, so playback starts
  fast and seeking stays responsive while the download continues.
- **Open torrents from outside the app** — Android VIEW intents for `magnet:`
  links are handled end-to-end (cold and warm start).
- **Torrent downloads manager** — Settings → *Data & privacy* lists what is on
  disk (sizes, file counts) with per-torrent delete and clear-all. Streamed
  torrents are kept on disk for **instant resume** from the watch history.
- **Debrid integration (optional)** — Real-Debrid / AllDebrid / TorBox keys
  resolve cached torrents to instant direct URLs; the on-device engine is the
  automatic fallback.
- Direct metadata providers: **TMDB** (built-in key, BYO override), **AniList**,
  and a six-provider ratings aggregate (IMDb, Rotten Tomatoes, Metacritic,
  TMDB, Trakt, MDBList) with local caching.
- **Trakt & Simkl** device-flow linking, watchlist/history import, and playback
  scrobbling — all straight from the device.
- **Noor Sync** — accountless cross-device sync through a dedicated Postgres
  (Supabase) instance using a least-privilege role. Settings, watchlist, lists,
  watch history, and add-ons sync per device identity; nothing to sign up for.
- Live TV (M3U), calendar, anime, kids, catalogs, custom lists, statistics.
- media_kit playback stack (MKV/TS/RMVB/FLV and more), subtitle and audio track
  switching, external add-on subtitles, torrent HUD (speed / peers / progress).
- Arabic RTL default with English option, fixed dark-bronze theme, phone and
  tablet layouts.

## Project layout

`lib/core` — API clients (NoorApi), models, catalog repository, torrent engine
bridge (`torrent/`), device sync (`sync/`), app state, and design tokens.
`lib/features` — one folder per screen group (home, media, player, torrent,
library, live_tv, anime, kids, calendar, catalog, settings, shell).
`lib/shared` — reusable widgets.

## Run and build

```sh
cd Noor  # repository root is the Flutter project
flutter pub get
flutter run
flutter build apk --release
flutter build appbundle --release
```

Build the iOS app on macOS with Xcode installed:

```sh
flutter build ios --release
```

Torrent playback: on Android the embedded libtorrent engine handles magnets
natively; on platforms without the engine, connect a Debrid service in
Settings → Integrations.

The checked-in Android release build uses the debug signing key until a private
release keystore is configured. Do not upload that build to an app store.
