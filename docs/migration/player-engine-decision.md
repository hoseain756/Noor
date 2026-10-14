# Video player engine decision

Date: 2026-10-13

## Decision

Keep the application's current `video_player` engine (`^2.11.1`) and redesign
the Flutter player around it. No dependency or native project change is needed
for the player redesign.

## Evidence

- The existing screen creates a `VideoPlayerController.networkUrl` from the
  app's already-resolved, signed stream URL. Playback history, resume position,
  scrobbling, external subtitles, audio selection when exposed by the backend,
  playback speed and episode progression already use this controller.
- Flutter's official package lists Android and iOS support. Its documentation
  identifies ExoPlayer as the Android backend and AVPlayer as the iOS backend;
  available formats remain platform and OS dependent:
  <https://pub.dev/packages/video_player>
- mpv describes itself as a command-line media player. Its listed system
  requirements name Linux, Windows and macOS, and its build instructions call
  for Meson and a native library toolchain. The repository does not document a
  maintained Flutter integration for Android and iOS:
  <https://github.com/mpv-player/mpv>
- `libmpv` is a low-level C API. Its embedding documentation describes a render
  API that requires the host to manage an OpenGL context, and a legacy native
  window-handle approach limited to X11, Win32 and macOS. A Flutter mobile
  integration would therefore require native rendering/lifecycle work and
  separately verified Android and iOS packaging:
  <https://github.com/mpv-player/mpv/blob/master/include/mpv/client.h>
- mpv's default license is GPLv2-or-later; its LGPLv2.1-or-later mode requires
  building with `-Dgpl=false`. This is additional distribution review for a
  feature the current mobile backend already supplies:
  <https://github.com/mpv-player/mpv#license>

## Trade-off and limitation

Retaining `video_player` preserves the already-integrated native mobile
backends, source signing, subtitles, progress reporting and navigation. This
does not promise support for every media format: decoding and streaming support
depends on each platform backend and device. An mpv migration should be
reconsidered only alongside a maintained Android+iOS Flutter bridge or a
verified native integration, device testing, and a licensing review.

## Implemented controls

The redesigned interface issues operations to the existing controller for
play/pause, seeking, mute/volume, speed and captions. Audio selection is shown
when the active backend exposes tracks. The aspect mode persists through the
existing app setting. Episode navigation resolves and signs streams through
the existing catalog and API path. Unsupported track selection continues to
show user feedback.
