/// Harbor web → Flutter port — the floating glass bottom navigation bar
/// ("glass dock"), translated from Harbor web
/// `src/components/harbor/chrome/glass-dock.tsx` plus the `--nav-*` /
/// `--glass-*` token ladder in its `globals.css` (verbatim fetch: Task 107-a;
/// adversarial review + translation contract: Task 107-b REVIEW.md).
///
/// Translation notes (why it looks nothing like Material):
///  - ONE shared sliding pill BEHIND the tabs (a `NavigationBar`/`TabBar`
///    draws per-section indicators and cannot follow a finger — per REVIEW.md
///    risk 1 the indicator is a custom `Stack` layer, not a Material widget).
///  - The pill's position is ONE value: a fractional tab index (`_frac`,
///    0..count-1). Idle changes animate 350ms `Cubic(0.2,0,0,1)`; a scrub drag
///    drives the fraction imperatively from raw pointer events (no implicit
///    animation in the way). The 1.08 scrub grow lives in the SAME Matrix4 as
///    the translation — a wrapper `ScaleTransition` would compose around the
///    untranslated origin and reproduce the web overshoot bug (REVIEW.md
///    risk 2).
///  - Scrub gesture (ported 1:1): enters on a ≥250ms hold OR a >6px move while
///    pressed; pill follows the pointer as a clamped fractional index; the
///    nearest tab lights as a PREVIEW while the real active tab's visuals are
///    suppressed; release commits exactly ONE navigation to `round(frac)`
///    (a fast flick advances one extra tab in the inline direction); cancel
///    snaps back with no navigation; `HapticFeedback.lightImpact` on start.
///  - The gesture uses a raw `Listener` instead of recognizers: Flutter
///    routes later events of a pressed pointer to the down-time hit-test path
///    (the idiomatic equivalent of the web's `setPointerCapture`), there is no
///    arena to lose vertical drags to, and quick taps are resolved here as
///    pure taps — exactly one tap, no double-fire.
///  - RTL: the tabs are laid out by a `Row` in the ambient `Directionality`
///    with the EXPLICIT per-direction order arrays from dock_tab.dart (same
///    visual order in both languages), and the pill translates by
///    `frac * slotW * dirSign` with `dirSign = -1` in RTL — never re-flipped.
///  - Auto-hide: the dock only renders the hidden state; the scroll hysteresis
///    lives in [GlassDockScrollHide], the host-page equivalent of the web's
///    passive `window.scroll` listener.
library;

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dock_tab.dart';

// ---------------------------------------------------------------------------
// Tokens (web `--nav-*` / `--glass-*`, dark appearance — Noor is dark-only).
// ---------------------------------------------------------------------------

/// Web `--glass-ease: cubic-bezier(0.2, 0, 0, 1)` — used for the pill slide,
/// the hidden slide and press-scale.
const Curve kDockEase = Cubic(0.2, 0, 0, 1);

const Duration _kDockSlideDuration = Duration(milliseconds: 350);
const Duration _kIconCrossfadeDuration = Duration(milliseconds: 150);
const Duration _kGrowDuration = Duration(milliseconds: 150);
const Duration _kReadyFadeDuration = Duration(milliseconds: 200);

/// Web `SCRUB_HOLD_MS` — hold this long to enter scrub without moving.
const Duration _kScrubHold = Duration(milliseconds: 250);

/// Web `SCRUB_MOVE_PX` — tap-vs-drag threshold while pressed.
const double _kScrubMovePx = 6;

/// Web `SCRUB_GROW` — pill grow while scrubbing (baked into the transform).
const double _kScrubGrow = 1.08;

/// Web `FLICK_PX_MS` — release velocity (px/ms) that advances one extra tab.
const double _kFlickPxPerMs = 0.5;

/// Web flick velocity window: only samples from the last 120ms count.
const int _kFlickSampleWindowMs = 120;

/// Web caps the velocity sample ring at 6 entries.
const int _kMaxScrubSamples = 6;

/// Web `--nav-radius: 9999px` (stadium capsule).
const double _kStadiumRadius = 9999;

// Glass recipe (Task 120 user mandate): the OLD detail back-pill surface —
// blur backdrop over a black/55 fill, 1px white/15 ring, soft black shadow —
// replaced the Harbor `--glass-*` cyan-tint recipe (tint `#BFE6F2` ring +
// sheen + panel fill `#10181C` @ .434 + saturate 1.35) so the dock, search
// button and detail pills all wear the same neutral dark glass.

// ---------------------------------------------------------------------------
// Size ladder (web window classes 1890–2002 + landscape last-wins override).
// ---------------------------------------------------------------------------

/// Resolved dock metrics for one window class (web `--nav-*` token values).
class GlassDockSizing {
  const GlassDockSizing({
    required this.barHeight,
    required this.tabHeight,
    required this.iconSize,
    required this.barWidth,
    required this.bottomOffset,
    required this.horizontalPadding,
    required this.blurSigma,
  });

  final double barHeight;
  final double tabHeight;
  final double iconSize;

  /// Final capsule width — the web `min(--nav-width, 100vw−16, −safeL−safeR)`
  /// chain is already resolved here.
  final double barWidth;
  final double bottomOffset;
  final double horizontalPadding;

  /// Backdrop blur: 14px, 12px below 600px viewport width (web).
  ///
  /// Task 136 (perf): RETIRED — the dock no longer renders a live
  /// BackdropFilter (it re-blurred the page beneath on every content frame;
  /// brutal on low-end GPUs). Kept in the ladder for sizing-API compat.
  final double blurSigma;

  /// Web `--nav-clearance` — the bottom padding page content needs so nothing
  /// hides behind the dock (height + bottom offset + safe bottom + 16px).
  double contentClearance({required double safeBottom}) =>
      barHeight + bottomOffset + safeBottom + 16;
}

/// Window-class ladder resolver: <360 / 360–599 (base) / 600–839 / 840–1199 /
/// 1200–1599 / ≥1600, with the landscape (`height ≤ 480`) override applied
/// LAST-WINS like the web source-order rule. `zoom` (app zoom, ≤1.1 on web)
/// and `kidsZoom` (1.08 in Kids Mode) multiply the size-bearing tokens;
/// hosts that lack those knobs keep the 1.0 defaults.
GlassDockSizing glassDockSizing({
  required Size viewport,
  EdgeInsets safePadding = EdgeInsets.zero,
  double zoom = 1.0,
  double kidsZoom = 1.0,
}) {
  final w = viewport.width;
  double barH, tabH, icon, width, bottom, pad;
  if (viewport.height <= 480) {
    // Landscape phone (max-height: 480 — source-order last, overrides all).
    barH = 48;
    tabH = 38;
    icon = 20;
    width = math.min(w * 0.7, 340);
    bottom = 8;
    pad = 6;
  } else if (w < 360) {
    barH = 54;
    tabH = 40;
    icon = 20;
    width = math.min(w - 24, 290);
    bottom = 12;
    pad = 6;
  } else if (w < 600) {
    // Phone base class.
    barH = 60;
    tabH = 44;
    icon = 22;
    width = math.min(w - 32, 330);
    bottom = 16;
    pad = 8;
  } else if (w < 840) {
    barH = 64;
    tabH = 48;
    icon = 22;
    width = 360;
    bottom = 20;
    pad = 8;
  } else if (w < 1200) {
    barH = 66;
    tabH = 50;
    icon = 24;
    width = 400;
    bottom = 24;
    pad = 8;
  } else if (w < 1600) {
    barH = 66;
    tabH = 50;
    icon = 24;
    width = 420;
    bottom = 24;
    pad = 8;
  } else {
    // TV class.
    barH = 78;
    tabH = 60;
    icon = 28;
    width = 490;
    bottom = 32;
    pad = 8;
  }
  final scale = zoom * kidsZoom;
  barH = math.max(barH, 76) * scale;
  tabH = math.max(tabH, 60) * scale;
  icon *= scale;
  width = math.max(width, math.min(w - 24, 390)) * scale;
  // Hard width guard (web `--nav-max` + safe-area caps).
  final viewportCap =
      math.max(0.0, math.min(w - 16, w - safePadding.horizontal));
  width = math.min(width, viewportCap);
  return GlassDockSizing(
    barHeight: barH,
    tabHeight: tabH,
    iconSize: icon,
    barWidth: width,
    bottomOffset: bottom,
    horizontalPadding: pad,
    blurSigma: w < 600 ? 12 : 14,
  );
}

// ---------------------------------------------------------------------------
// GlassDock.
// ---------------------------------------------------------------------------

/// The glass dock: a floating stadium capsule fixed to the bottom-center with
/// one shared sliding pill behind equal-flex tabs.
///
/// The widget is self-contained (flutter + [dock_tab.dart] only). Mount it in
/// the shell's `Stack` (bottom-center) and give it:
///  - [tabs]: already filtered + ordered (see [dockTabsFor] and the explicit
///    `kDockOrder*` arrays — pass them in logical order, do not flip again).
///  - [activeId]: the tab that is really active (see [dockActiveTabId]).
///  - [onTabSelected]: the ONE navigation callback (web `resetTo(view)`).
///  - [hidden]: externally driven hide (scroll auto-hide via
///    [GlassDockScrollHide], or route-based chrome hiding).
class GlassDock extends StatefulWidget {
  const GlassDock({
    super.key,
    required this.tabs,
    required this.activeId,
    required this.onTabSelected,
    this.languageCode,
    this.hidden = false,
    this.reduceMotion = false,
    this.reduceTransparency = false,
    this.zoom = 1.0,
    this.kidsZoom = 1.0,
  });

  /// Tabs to render, in display order (filter + order with [dockTabsFor]).
  /// Must contain ≥1 tab; the scrub gesture additionally requires ≥2.
  final List<DockTab> tabs;

  /// Id of the active tab. When it is NOT among [tabs] (reachable web quirk:
  /// enabling Kids Mode from Settings does not navigate) the pill gracefully
  /// falls back to slot 0 and no tab reports itself selected — mirroring the
  /// web `Math.max(0, findIndex(…))` fallback.
  final String activeId;

  /// Exactly-one navigation commit: tab taps, scrub release and screen-reader
  /// activation all funnel here (web `resetTo({kind: 'view', view})`).
  final ValueChanged<DockTab> onTabSelected;

  /// Language code for labels/`Semantics` (Arabic regex like the web). When
  /// null, the ambient `Directionality` decides (`rtl` → Arabic).
  final String? languageCode;

  /// Effective hidden state (slide below screen + fade + ignore pointers +
  /// exclude semantics). Drive it from [GlassDockScrollHide] and/or routes.
  final bool hidden;
  final bool reduceMotion;
  final bool reduceTransparency;

  /// App zoom multiplier (web `--nav-zoom`, ≤1.1). Defaults to 1.0.
  final double zoom;

  /// Kids Mode size multiplier (web `--nav-kids`, 1.08). Defaults to 1.0.
  final double kidsZoom;

  @override
  State<GlassDock> createState() => _GlassDockState();
}

class _GlassDockState extends State<GlassDock> with TickerProviderStateMixin {
  // kPrimaryMouseButton, kept as a literal to stay import-minimal.
  static const _leftMouseButton = 1;

  /// Idle/snap motion: lerps BOTH the pill fraction and its scale over the
  /// same 350ms curve (web: one transform transition).
  late final AnimationController _motion;
  late final CurvedAnimation _motionEase;
  double _motionFracFrom = 0;
  double _motionFracTo = 0;
  double _motionScaleFrom = 1;
  double _motionScaleTo = 1;

  /// Scrub grow: 1 → 1.08 over 150ms (web ease-out quad). Composed into the
  /// pill's single Matrix4 at paint time, never a separate scale layer.
  late final AnimationController _grow;
  late final CurvedAnimation _growEase;

  // THE single indicator state. Exactly one value (fractional slot index)
  // drives the pill — the state-driven replacement for the web's DOM-write
  // `writePill` choreography (which REVIEW.md said not to port).
  double _frac = 0;
  double _scale = 1;
  bool _measured = false; // web `data-ready` equivalent (fade after measure)

  bool _scrubbing = false;
  int? _litIndex; // scrub preview: nearest slot lights up
  int? _pressedIndex; // press scale 0.96 + state layer

  bool _reduceMotion = false;
  bool _isRtl = false;
  int _dirSign = 1;
  double _pad = 8;
  double _trackW = 0;
  double _slotW = 0;

  // Scrub gesture bookkeeping (web ScrubGesture).
  _PendingGesture? _pending;
  Timer? _holdTimer;
  final List<({double x, int t})> _samples = [];
  Stopwatch? _scrubClock;

  @override
  void initState() {
    super.initState();
    _motion = AnimationController(vsync: this, duration: _kDockSlideDuration);
    _motionEase = CurvedAnimation(parent: _motion, curve: kDockEase);
    _motionEase.addListener(_onMotionTick);
    _grow = AnimationController(vsync: this, duration: _kGrowDuration);
    _growEase = CurvedAnimation(parent: _grow, curve: Curves.easeOutQuad);
    _growEase.addListener(_onGrowTick);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion =
        widget.reduceMotion || MediaQuery.disableAnimationsOf(context);
  }

  @override
  void didUpdateWidget(covariant GlassDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    _reduceMotion =
        widget.reduceMotion || MediaQuery.disableAnimationsOf(context);
    final idsChanged = !_sameTabIds(oldWidget.tabs, widget.tabs);
    if (idsChanged && _scrubbing) {
      // Defensive: the tab set changed mid-scrub (language switch / kids
      // toggle while dragging). Abort the gesture without navigating.
      _holdTimer?.cancel();
      _holdTimer = null;
      _pending = null;
      _scrubClock = null;
      _samples.clear();
      _scrubbing = false;
      _litIndex = null;
      _pressedIndex = null;
    }
    if (!_scrubbing && (idsChanged || oldWidget.activeId != widget.activeId)) {
      // Web re-seats the pill on active change AND on tab set/order change
      // (the `tabSig` re-measure) — animate to the resolved slot.
      _startMotion(toFrac: _resolvedActiveSlot.toDouble(), toScale: 1);
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _motionEase.dispose();
    _motion.dispose();
    _growEase.dispose();
    _grow.dispose();
    super.dispose();
  }

  // -- pill motion -----------------------------------------------------------

  /// Active slot with the web fallback: `Math.max(0, findIndex(...))` — when
  /// the active tab is hidden by filtering, the pill rests on slot 0 and no
  /// tab is selected (see [GlassDock.activeId]).
  int get _resolvedActiveSlot {
    final i = widget.tabs.indexWhere((tab) => tab.id == widget.activeId);
    return i >= 0 ? i : 0;
  }

  void _startMotion({required double toFrac, required double toScale}) {
    if (_motion.isAnimating &&
        _motionFracTo == toFrac &&
        _motionScaleTo == toScale) {
      return; // already gliding there (nav + release can both ask)
    }
    _motion.stop();
    _grow.stop();
    _motionFracFrom = _frac;
    _motionFracTo = toFrac;
    _motionScaleFrom = _scale;
    _motionScaleTo = toScale;
    _motion.duration = _reduceMotion ? Duration.zero : _kDockSlideDuration;
    _motion.forward(from: 0);
  }

  void _onMotionTick() {
    final t = _motionEase.value;
    setState(() {
      _frac = _lerp(_motionFracFrom, _motionFracTo, t);
      _scale = _lerp(_motionScaleFrom, _motionScaleTo, t);
    });
  }

  void _onGrowTick() {
    setState(() => _scale = 1 + (_kScrubGrow - 1) * _growEase.value);
  }

  // -- scrub gesture (web ScrubGesture + pointer handlers) -------------------

  void _onPointerDown(PointerDownEvent event) {
    if (widget.hidden) return;
    if (_pending != null) return; // multi-touch: first pointer owns the gesture
    if (event.kind == PointerDeviceKind.mouse &&
        event.buttons != _leftMouseButton) {
      return;
    }
    _pending = _PendingGesture(
      pointer: event.pointer,
      startX: event.localPosition.dx,
      startY: event.localPosition.dy,
    );
    setState(() => _pressedIndex = _slotForLocalX(event.localPosition.dx));
    _holdTimer = Timer(_kScrubHold, () {
      final pending = _pending;
      if (pending != null && !_scrubbing) {
        _enterScrub(pending.startX, pending.pointer);
      }
    });
  }

  void _onPointerMove(PointerMoveEvent event) {
    final pending = _pending;
    if (pending == null || event.pointer != pending.pointer) return;
    if (!_scrubbing) {
      final distance =
          (event.localPosition - Offset(pending.startX, pending.startY))
              .distance;
      if (distance > _kScrubMovePx) {
        // >6px move in ANY direction enters scrub (cancel the hold timer).
        _holdTimer?.cancel();
        _holdTimer = null;
        _enterScrub(event.localPosition.dx, event.pointer);
      }
      return;
    }
    _updateScrub(event.localPosition.dx);
  }

  void _onPointerUp(PointerUpEvent event) {
    final pending = _pending;
    if (pending == null || event.pointer != pending.pointer) return;
    _holdTimer?.cancel();
    _holdTimer = null;
    _pending = null;
    if (!_scrubbing) {
      // Plain tap: never entered scrub → exactly one selection, no snap.
      setState(() => _pressedIndex = null);
      if (widget.tabs.isNotEmpty) {
        widget
            .onTabSelected(widget.tabs[_slotForLocalX(event.localPosition.dx)]);
      }
      return;
    }
    _commitScrub();
  }

  void _onPointerCancel(PointerCancelEvent event) {
    final pending = _pending;
    if (pending == null || event.pointer != pending.pointer) return;
    _holdTimer?.cancel();
    _holdTimer = null;
    _pending = null;
    if (!_scrubbing) {
      setState(() => _pressedIndex = null);
      return;
    }
    // Cancel mid-scrub: snap back to the still-active tab, NO navigation.
    _samples.clear();
    _scrubClock = null;
    setState(() {
      _scrubbing = false;
      _litIndex = null;
      _pressedIndex = null; // cancel clears the press state too
    });
    _startMotion(toFrac: _resolvedActiveSlot.toDouble(), toScale: 1);
  }

  void _enterScrub(double localX, int pointer) {
    final pending = _pending;
    if (_scrubbing ||
        pending == null ||
        pending.pointer != pointer ||
        widget.tabs.length < 2) {
      return;
    }
    _motion.stop(); // transitions OFF while scrubbing (web data-scrub)
    _grow.duration = _reduceMotion ? Duration.zero : _kGrowDuration;
    _grow.forward(from: 0);
    _scrubClock = Stopwatch()..start();
    _samples.clear();
    setState(() {
      _scrubbing = true;
      // End the press affordance: once scrub takes over, the pill grow + the
      // lit preview ARE the feedback (web: pointer capture moves :active off
      // the button). Also guarantees no slot can stay pressed after release.
      _pressedIndex = null;
    });
    _updateScrub(localX); // seed the pill at the pointer + light nearest slot
    HapticFeedback.lightImpact(); // web navigator.vibrate(10)
  }

  void _updateScrub(double localX) {
    final count = widget.tabs.length;
    if (count < 2 || _scrubClock == null) return;
    final frac = _fracForLocalX(localX);
    _samples.add((x: localX, t: _scrubClock!.elapsedMilliseconds));
    if (_samples.length > _kMaxScrubSamples) _samples.removeAt(0);
    setState(() {
      _frac = frac; // fractional index, clamped to the capsule
      _litIndex = _clampSlot(frac.round(), count);
    });
  }

  void _commitScrub() {
    final count = widget.tabs.length;
    if (count == 0) return;
    var target = _clampSlot(_frac.round(), count);
    // Flick: velocity over the last ≤120ms of samples; a fast release in the
    // physical direction advances one extra tab in the INLINE direction
    // (sign(v) × dirSign), clamped — never wraps past the ends.
    final now = _scrubClock?.elapsedMilliseconds ?? 0;
    final recent = _samples
        .where((sample) => now - sample.t <= _kFlickSampleWindowMs)
        .toList(growable: false);
    if (recent.length >= 2) {
      final dt = recent.last.t - recent.first.t;
      if (dt > 0) {
        final velocity = (recent.last.x - recent.first.x) / dt; // px/ms
        if (velocity.abs() > _kFlickPxPerMs) {
          target =
              _clampSlot(target + (velocity > 0 ? 1 : -1) * _dirSign, count);
        }
      }
    }
    _samples.clear();
    _scrubClock = null;
    setState(() {
      _scrubbing = false;
      _litIndex = null;
      _pressedIndex = null; // release MUST clear the press scale + state layer
    });
    _startMotion(toFrac: target.toDouble(), toScale: 1); // 350ms snap
    final tab = widget.tabs[target];
    if (tab.id != widget.activeId) {
      widget.onTabSelected(tab); // exactly ONE navigation commit
    }
  }

  // -- geometry helpers ------------------------------------------------------

  /// Inline-axis position inside the track from a capsule-local x (web flips
  /// against `rect.right` in RTL: `rect.right − clientX`).
  double _inlinePos(double localX) {
    final x = _clampD(localX - _pad, 0, _trackW);
    return _isRtl ? _trackW - x : x;
  }

  /// Web `fracFor(clientX)`: `clamp(pos/slotW − 0.5, 0, count−1)` — the pill
  /// CENTER tracks the pointer.
  double _fracForLocalX(double localX) {
    final count = widget.tabs.length;
    if (count == 0 || _slotW <= 0) return 0;
    return _clampD(_inlinePos(localX) / _slotW - 0.5, 0, count - 1);
  }

  int _slotForLocalX(double localX) {
    final count = widget.tabs.length;
    if (count == 0 || _slotW <= 0) return 0;
    return _clampSlot((_inlinePos(localX) / _slotW).floor(), count);
  }

  // -- build -----------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    _isRtl = rtl;
    _dirSign = rtl ? -1 : 1;

    // Label language: explicit code wins, else the ambient direction (web:
    // settings.uiLanguage drives both label and direction).
    final arabic = widget.languageCode != null
        ? dockIsArabicLanguage(widget.languageCode)
        : rtl;
    final navLabel = arabic ? 'التنقل الرئيسي' : 'Primary navigation';

    final activeIndex =
        widget.tabs.indexWhere((tab) => tab.id == widget.activeId);
    final hasActive = activeIndex >= 0;

    return Semantics(
      container: true,
      label: navLabel,
      child: ExcludeSemantics(
        // aria-hidden equivalent: the hidden dock leaves the a11y tree.
        excluding: widget.hidden,
        child: IgnorePointer(
          ignoring: widget.hidden,
          child: AnimatedSlide(
            offset: widget.hidden ? const Offset(0, 1) : Offset.zero,
            duration: _reduceMotion ? Duration.zero : _kDockSlideDuration,
            curve: kDockEase,
            child: AnimatedOpacity(
              opacity: widget.hidden ? 0 : 1,
              duration: _reduceMotion ? Duration.zero : _kDockSlideDuration,
              curve: kDockEase,
              child: Padding(
                // Safe area (web: bottom offset + env(safe-area-inset-bottom)).
                padding: EdgeInsets.only(
                  bottom: MediaQuery.paddingOf(context).bottom,
                ),
                child: Center(
                  child: _buildDock(media, activeIndex, hasActive, arabic),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDock(
    MediaQueryData media,
    int activeIndex,
    bool hasActive,
    bool arabic,
  ) {
    final sizing = glassDockSizing(
      viewport: media.size,
      safePadding: media.padding,
      zoom: widget.zoom,
      kidsZoom: widget.kidsZoom,
    );
    return Padding(
      padding: EdgeInsets.only(bottom: sizing.bottomOffset),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: sizing.barWidth),
        child: SizedBox(
          height: sizing.barHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final trackW = _clampD(
                constraints.maxWidth - 2 * sizing.horizontalPadding,
                0,
                constraints.maxWidth,
              );
              final slotW =
                  widget.tabs.isEmpty ? 0.0 : trackW / widget.tabs.length;
              // First measure: seed the pill without animation — the Flutter
              // equivalent of the web's `data-ready` first-paint gate (and the
              // reason the DOM ResizeObserver choreography was dropped).
              if (!_measured && slotW > 0 && widget.tabs.isNotEmpty) {
                _measured = true;
                _frac = _resolvedActiveSlot.toDouble();
                _scale = 1;
              }
              _pad = sizing.horizontalPadding;
              _trackW = trackW;
              _slotW = slotW;

              return Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
                child: DecoratedBox(
                  // 1px white/15 ring painted above the clipped glass + the
                  // old back-pill soft shadow (Task 120 recipe swap).
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(_kStadiumRadius),
                    border: Border.all(
                        color: Theme.of(context)
                            .colorScheme
                            .outlineVariant
                            .withValues(alpha: .65)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: .35),
                        blurRadius: 14,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(_kStadiumRadius),
                    child: Stack(
                      children: [
                        // Glass backdrop — Task 136 (perf): the LIVE
                        // BackdropFilter used to re-blur everything behind
                        // the dock on EVERY frame the content changed (any
                        // scroll/rail drag before the auto-hide kicks in),
                        // which is brutal on low-end GPUs. The dock now
                        // wears the same recipe as a static fill — the 1px
                        // white/15 ring and the drop shadow above are
                        // unchanged; the fill reads a touch darker to
                        // compensate for the lost blur diffusion.
                        Positioned.fill(
                          child: ColoredBox(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHigh
                                .withValues(
                                    alpha: widget.reduceTransparency ? 1 : .96),
                          ),
                        ),
                        // Track: pill BEHIND equal-flex tabs (web .dock-track).
                        Center(
                          child: Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: sizing.horizontalPadding,
                            ),
                            child: SizedBox(
                              width: trackW > 0 ? trackW : null,
                              height: sizing.tabHeight,
                              child: Stack(
                                children: [
                                  if (slotW > 0)
                                    PositionedDirectional(
                                      start: 0, // web inset-inline-start: 0
                                      top: 0,
                                      width: slotW,
                                      height: sizing.tabHeight,
                                      child: ExcludeSemantics(
                                        child: AnimatedOpacity(
                                          opacity: _measured ? 1 : 0,
                                          duration: _reduceMotion
                                              ? Duration.zero
                                              : _kReadyFadeDuration,
                                          child: Transform(
                                            // Grow + translation in ONE
                                            // transform, composed around the
                                            // pill center (never a wrapper
                                            // ScaleTransition).
                                            alignment: Alignment.center,
                                            transformHitTests: false,
                                            transform: Matrix4.identity()
                                              ..translateByDouble(
                                                _frac * slotW * _dirSign,
                                                0,
                                                0,
                                                1,
                                              )
                                              ..scaleByDouble(
                                                  _scale, _scale, 1, 1),
                                            child: DecoratedBox(
                                              decoration: BoxDecoration(
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .primaryContainer,
                                                borderRadius:
                                                    BorderRadius.circular(
                                                  _kStadiumRadius,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  Row(
                                    children: [
                                      for (var i = 0;
                                          i < widget.tabs.length;
                                          i++)
                                        Expanded(
                                          child: _DockTabButton(
                                            tab: widget.tabs[i],
                                            // Preview lighting while scrubbing
                                            // suppresses the real active tab's
                                            // visuals — exactly ONE indicator.
                                            highlighted: _scrubbing
                                                ? _litIndex == i
                                                : i == activeIndex,
                                            selected:
                                                hasActive && i == activeIndex,
                                            pressed: _pressedIndex == i,
                                            arabic: arabic,
                                            iconSize: sizing.iconSize,
                                            reduceMotion: _reduceMotion,
                                            onActivate: () => widget
                                                .onTabSelected(widget.tabs[i]),
                                          ),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  bool _sameTabIds(List<DockTab> a, List<DockTab> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }
}

/// The pressed pointer's identity — only that pointer may drive the gesture
/// (multi-touch ignored, like the web pointerId filter).
class _PendingGesture {
  const _PendingGesture({
    required this.pointer,
    required this.startX,
    required this.startY,
  });

  final int pointer;
  final double startX;
  final double startY;
}

/// One dock tab button: icon cross-fade (outline ↔ filled, 150ms), press
/// scale 0.96 with a M3-ish state layer, and button semantics with a
/// selected state (the aria-current equivalent). Taps are resolved by the
/// dock's Listener — this button only carries visuals + semantics.
class _DockTabButton extends StatelessWidget {
  const _DockTabButton({
    required this.tab,
    required this.highlighted,
    required this.selected,
    required this.pressed,
    required this.arabic,
    required this.iconSize,
    required this.reduceMotion,
    required this.onActivate,
  });

  final DockTab tab;

  /// Visual active state (real active when idle; scrub preview while
  /// scrubbing — the real active tab's visuals are suppressed then).
  final bool highlighted;

  /// Semantics truth: follows the REAL active tab even mid-scrub (web keeps
  /// aria-current on it while suppressing its visuals).
  final bool selected;
  final bool pressed;
  final bool arabic;
  final double iconSize;
  final bool reduceMotion;
  final VoidCallback onActivate;

  @override
  Widget build(BuildContext context) {
    final duration = reduceMotion ? Duration.zero : _kIconCrossfadeDuration;
    return FocusableActionDetector(
        mouseCursor: SystemMouseCursors.click,
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) {
            onActivate();
            return null;
          })
        },
        child: Semantics(
          button: true,
          selected: selected,
          label: dockTabLabel(tab, arabic: arabic),
          onTap: onActivate,
          child: AnimatedScale(
            scale: pressed ? 0.96 : 1, // web :active scale(--glass-press-scale)
            duration: duration,
            curve: kDockEase,
            child: Stack(
              children: [
                // State layer (web .md-state active 0.1 on currentColor).
                Positioned.fill(
                  child: AnimatedOpacity(
                    opacity: pressed ? 1 : 0,
                    duration: duration,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(_kStadiumRadius),
                      ),
                    ),
                  ),
                ),
                Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(tab.iconOutline,
                      size: iconSize,
                      color: highlighted
                          ? Theme.of(context).colorScheme.onPrimaryContainer
                          : Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(height: 3),
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 3),
                      child: Text(dockTabLabel(tab, arabic: arabic),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context)
                              .textTheme
                              .labelSmall
                              ?.copyWith(
                                  fontSize: 10,
                                  fontWeight: highlighted
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                  color: highlighted
                                      ? Theme.of(context)
                                          .colorScheme
                                          .onPrimaryContainer
                                      : Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant))),
                ])),
              ],
            ),
          ),
        ));
  }
}

// ---------------------------------------------------------------------------
// Scroll auto-hide helper (web passive window.scroll listener replacement).
// ---------------------------------------------------------------------------

/// Scroll-driven auto-hide for [GlassDock] — the per-page replacement for the
/// web build's passive `window.scroll` listener (Flutter has no window
/// scroll; REVIEW.md risk 6).
///
/// Mix into the host page's `State`, wrap the page's primary scrollable in a
/// `NotificationListener<ScrollNotification>` that forwards to
/// [handleGlassDockScroll], and pass `glassDockHidden` into
/// `GlassDock.hidden`. Same hysteresis as the web dock:
/// hide on `y > 120 && dy > +4`, reveal on `dy < -4` or `y <= 120`.
mixin GlassDockScrollHide<T extends StatefulWidget> on State<T> {
  bool _glassDockHidden = false;

  /// Web `settings.dockAutoHide` (default true) — override to wire a flag,
  /// e.g. `bool get dockAutoHide => app.dockAutoHide;`.
  bool get dockAutoHide => true;

  /// Current hidden state for `GlassDock.hidden`.
  bool get glassDockHidden => _glassDockHidden;

  /// Force-reveal (tab switch, page change, …).
  void revealGlassDock() {
    if (_glassDockHidden) setState(() => _glassDockHidden = false);
  }

  /// Wire as the `onNotification` of a NotificationListener around the page's
  /// primary scrollable. Always returns false (never consumes).
  bool handleGlassDockScroll(ScrollNotification notification) {
    if (notification.metrics.axis != Axis.vertical) return false;
    if (notification is! ScrollUpdateNotification) return false;
    if (!dockAutoHide) {
      if (_glassDockHidden) setState(() => _glassDockHidden = false);
      return false;
    }
    final y = notification.metrics.pixels;
    final dy = notification.scrollDelta ?? 0;
    if (y > 120 && dy > 4) {
      if (!_glassDockHidden) setState(() => _glassDockHidden = true);
    } else if (dy < -4 || y <= 120) {
      if (_glassDockHidden) setState(() => _glassDockHidden = false);
    }
    return false;
  }
}

// -- tiny clamping helpers (num.clamp returns `num`; keep types exact) ------

double _lerp(double a, double b, double t) => a + (b - a) * t;

double _clampD(double value, double min, double max) =>
    value < min ? min : (value > max ? max : value);

int _clampSlot(int value, int count) {
  if (count <= 0) return 0;
  if (value < 0) return 0;
  if (value > count - 1) return count - 1;
  return value;
}
