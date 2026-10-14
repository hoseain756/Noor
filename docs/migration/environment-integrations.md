# Horse mobile app and server environment integrations

The Flutter client talks to the Horse HTTP API. Server credentials stay in the
Horse web server environment; the mobile build receives only the Horse API
base URL (`HORSE_API_BASE_URL`). Per-user TMDB and Debrid keys are stored in
platform secure storage and sent to Horse only for requests that need them.
This separation also matches [Supabase's connection guidance](https://supabase.com/docs/guides/database/connecting-to-postgres): serverless backends use the transaction pooler, while database migrations use a direct or session connection. The Flutter client is not a database client.

## Environment variable map

| Server variable | Purpose in Horse | Mobile integration |
|---|---|---|
| `POSTGRES_URL` | Runtime database connection through the transaction pooler. | Account sync, sessions, and server-side state through Horse APIs. `/api/health` reports reachability and row-security coverage. |
| `POSTGRES_URL_NON_POOLING` | Migration connection used during deployment only. | No direct mobile use. The app never connects to Postgres. |
| `ENCRYPTION_KEY` | Preferred key for encrypting account snapshots and saved provider data at rest. | Transparent to mobile; values never enter the APK. |
| `HORSE_TOKEN_SECRET` | Legacy/fallback encryption and signing material. | Transparent to mobile; values never enter the APK. |
| `HORSE_OLD_TOKEN_SECRET` | Decrypts older encrypted records during key rotation. | Transparent to mobile; values never enter the APK. |
| `CRON_SECRET` | Authorizes scheduled server maintenance. | Server-only; no mobile request needs it. |
| `RESEND_API_KEY` | Sends account verification and password recovery emails. | Account actions use Horse auth routes; `/api/integrations/status` reports whether Resend is configured, without returning the key. |
| `MAIL_FROM` | Sender address used by transactional mail. | Server-only mail setting. |
| `APP_URL` | Optional public URL for links in account emails. | Server-only; deployment URL detection is used when unset. |
| `ENGINE_URL` | Server-side relay target for the optional external torrent engine. | Playback reads `/api/media/capabilities` and sends JSON engine calls through Horse. |
| `ENGINE_PUBLIC_URL` | Browser/device-reachable base for external engine media. | Playback receives the public media URL only when the external engine is active. |
| `ENGINE_API_KEY` | Server-to-engine credential; Horse issues short-lived media tokens. | Never sent as a static client secret. |
| `TMDB_ACCESS_TOKEN` | Server TMDB access for artwork and metadata. | `/api/tmdb`; availability appears in `/api/integrations/status`. A user's own TMDB key remains in secure device storage. |
| `TRAKT_CLIENT_ID` | Enables Trakt linking, import, sync, and supported ratings. | `/api/trakt/*`; availability appears in `/api/integrations/status`. |
| `TRAKT_CLIENT_SECRET` | Optional server-side Trakt token exchange secret. | Never included in the mobile app. |
| `SIMKL_CLIENT_ID` | Enables Simkl device linking. | `/api/simkl/*`; availability appears in `/api/integrations/status`. |
| `SIMKL_CLIENT_SECRET` | Optional confidential-app token exchange secret. | Never included in the mobile app. |
| `OMDB_API_KEY` | Adds IMDb, Rotten Tomatoes, and Metacritic data where available. | `/api/ratings`; availability appears in `/api/integrations/status`. |
| `MDBLIST_API_KEY` | Adds MDBList ratings. | `/api/ratings`; availability appears in `/api/integrations/status`. |

## In-app server status

Settings → Connected services now checks three server endpoints:

- `/api/health` for database reachability and row-level security coverage.
- `/api/integrations/status` for TMDB, Trakt, Simkl, Resend, OMDb, and MDBList
  configuration booleans.
- `/api/media/capabilities` for the available torrent engine mode.

The screen shows configuration status only; presence does not guarantee a
provider key is valid, has quota, or can currently deliver email. It never
displays server keys, database
connection strings, internal engine addresses, or server error details. A
missing or unreachable endpoint is shown as unknown so older deployments and
temporary network failures are distinguishable from an unconfigured provider.

## Deployment boundary

Adding these environment variable names to an example file does not configure
the running deployment. Set server values in the Horse server's ignored local
environment file or in Vercel Project Settings for the intended environments.
Keep migration credentials and API secrets on the server. Do not pass them to
Flutter through `--dart-define`, assets, preferences, or source control.

The mobile app uses the configured Horse deployment by default. For a separate
Horse server, provide its base URL at build time:

```sh
flutter build apk --dart-define=HORSE_API_BASE_URL=https://your-horse.example
```
