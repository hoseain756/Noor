# Horse for Flutter

Native Flutter client for Horse on Android phones, iPhones, and tablets.

## Included features

- Home, Anime, Kids, and My Library as the only primary destinations.
- Bottom navigation on phones and a tablet navigation rail on wider screens.
- Cinemeta and installed Stremio add-on catalogs, metadata, and stream discovery.
- Add-on install, enable/disable, removal, Stremio collection sync, and Horse account sync.
- Trakt and Simkl account linking, watchlist/history import, and playback scrobbling.
- Real-Debrid, AllDebrid, and TorBox key verification and cached torrent resolution.
- A native video player for HTTP/HLS and supported torrent sources, with seek, playback controls, orientation handling, and progress sync.
- Watchlist, watch history, playback progress, and viewing statistics.
- Arabic RTL as the default language, English as an option, and the fixed Horse dark-bronze theme.

## Project layout

`lib/core` contains the API client, models, catalog repository, app state, and design tokens. `lib/features` groups each app feature by its screen and related UI. `lib/shared` contains reusable widgets.

## Server

The default server is `https://horse-silk.vercel.app`. Change it from Settings if you host Horse elsewhere. For a build-time override:

```sh
flutter build apk --dart-define=HORSE_API_BASE_URL=https://your-horse.example
```

Content catalogs work without signing in. A Horse account syncs add-ons, watchlist, history, and playback progress across devices. A Stremio account syncs the add-on collection. Trakt and Simkl linking require a Horse account and server-side provider configuration. Debrid API keys are kept in device secure storage and sent only to the Horse server when validating or resolving a torrent.

## Run and build

```sh
cd mobile_app
flutter pub get
flutter run
flutter build apk --release
flutter build appbundle --release
```

Build the iOS app on macOS with Xcode installed:

```sh
flutter build ios --release
```

Direct HTTP and HLS streams are played by the platform media player. Magnet/torrent sources use the connected Debrid service when configured; otherwise the Horse server must expose a reachable torrent engine.

The checked-in Android release build uses the debug signing key until a private release keystore is configured. Do not upload that build to an app store. Build iOS on macOS with Xcode; iOS compilation is not available from Windows.
