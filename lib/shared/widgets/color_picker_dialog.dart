import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/theme/horse_theme.dart';

/// Width of the hue ring in the picker wheel (shared by state + painter).
const double _kRingWidth = 30;

/// Noor color picker — HSV wheel + saturation/value square + hex input +
/// curated presets. Pure Flutter (no third-party packages), styled to the
/// app's dark/bronze design language.
///
/// Returns the picked color as `#RRGGBB` (uppercase), or null when dismissed.
Future<String?> showNoorColorPicker(
  BuildContext context, {
  required String initialHex,
  String? title,
  bool english = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _NoorColorPickerDialog(
      initialHex: initialHex,
      title: title,
      english: english,
    ),
  );
}

class _NoorColorPickerDialog extends StatefulWidget {
  const _NoorColorPickerDialog({
    required this.initialHex,
    this.title,
    required this.english,
  });

  final String initialHex;
  final String? title;
  final bool english;

  @override
  State<_NoorColorPickerDialog> createState() => _NoorColorPickerDialogState();
}

class _NoorColorPickerDialogState extends State<_NoorColorPickerDialog> {
  static const _presets = <String>[
    '#FFFFFF', '#C99C62', '#F5C778', '#FFD66E', '#9CE8B8', '#8ED5FF',
    '#FF8E8E', '#FF7AB2', '#B39DDB', '#8A8F98', '#4A4D50', '#000000',
  ];

  static const double _wheelSide = 258;

  late HSVColor _hsv;
  late final TextEditingController _hexCtrl;
  final _hexFocus = FocusNode();
  bool _hexEditing = false;

  @override
  void initState() {
    super.initState();
    _hsv = HSVColor.fromColor(_parseHex(widget.initialHex));
    _hexCtrl = TextEditingController(text: _hexOf(_hsv));
    _hexFocus.addListener(() {
      if (!_hexFocus.hasFocus && mounted) {
        _hexCtrl.text = _hexOf(_hsv);
        setState(() => _hexEditing = false);
      }
    });
  }

  @override
  void dispose() {
    _hexCtrl.dispose();
    _hexFocus.dispose();
    super.dispose();
  }

  // ── Color plumbing ───────────────────────────────────────────────────────

  static Color _parseHex(String raw) {
    final hex = raw.trim().replaceFirst('#', '');
    final parsed = int.tryParse(hex, radix: 16) ?? 0xFFFFFF;
    return Color(0xFF000000 | parsed);
  }

  static String _hexOf(HSVColor hsv) {
    final c = hsv.toColor();
    final r = ((c.r * 255).round()).clamp(0, 255).toInt();
    final g = ((c.g * 255).round()).clamp(0, 255).toInt();
    final b = ((c.b * 255).round()).clamp(0, 255).toInt();
    final hex = (r << 16) | (g << 8) | b;
    return '#${hex.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  void _update(HSVColor next) {
    setState(() {
      _hsv = next;
      if (!_hexEditing) _hexCtrl.text = _hexOf(_hsv);
    });
  }

  void _applyHex(String text) {
    final hex = text.trim().replaceFirst('#', '');
    if (hex.length != 6) return;
    final parsed = int.tryParse(hex, radix: 16);
    if (parsed == null) return;
    _update(HSVColor.fromColor(Color(0xFF000000 | parsed)));
  }

  void _onWheelPoint(Offset local, Size wheelSize) {
    final center = Offset(wheelSize.width / 2, wheelSize.height / 2);
    final dist = (local - center).distance;
    final innerRadius = wheelSize.width / 2 - _kRingWidth - 3;
    if (dist > innerRadius) {
      // Hue ring: angle 0 at the top, clockwise.
      var degrees =
          math.atan2(local.dy - center.dy, local.dx - center.dx) * 180 /
                  math.pi +
              90;
      degrees %= 360;
      _update(_hsv.withHue(degrees));
    } else {
      // Saturation/value square inscribed in the inner circle.
      final side = innerRadius * math.sqrt2;
      final origin = Offset(center.dx - side / 2, center.dy - side / 2);
      final dx = (local.dx - origin.dx).clamp(0.0, side);
      final dy = (local.dy - origin.dy).clamp(0.0, side);
      _update(_hsv.withSaturation(side == 0 ? 0 : dx / side)
          .withValue(side == 0 ? 1 : 1 - dy / side));
    }
  }
  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final color = _hsv.toColor();
    return AlertDialog(
      backgroundColor: HorseTheme.raised,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: HorseTheme.line),
      ),
      titlePadding: const EdgeInsetsDirectional.fromSTEB(24, 20, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 14, 24, 6),
      actionsPadding: const EdgeInsetsDirectional.fromSTEB(16, 4, 16, 14),
      title: Text(
        widget.title ?? (widget.english ? 'Pick a color' : 'اختر لونًا'),
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      content: SizedBox(
        width: 300,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTapDown: (d) => _onWheelPoint(d.localPosition,
                    Size.square(_wheelSide)),
                onPanStart: (d) => _onWheelPoint(
                    d.localPosition, Size.square(_wheelSide)),
                onPanUpdate: (d) => _onWheelPoint(
                    d.localPosition, Size.square(_wheelSide)),
                child: SizedBox(
                  width: _wheelSide,
                  height: _wheelSide,
                  child: LayoutBuilder(builder: (context, constraints) {
                    final side = constraints.maxWidth;
                    final innerRadius = side / 2 - _kRingWidth - 3;
                    final squareSide = innerRadius * math.sqrt2;
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        CustomPaint(
                          size: Size.square(side),
                          painter: _WheelPainter(hsv: _hsv),
                        ),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: SizedBox(
                            width: squareSide,
                            height: squareSide,
                            child: CustomPaint(
                              size: Size.square(squareSide),
                              painter: _SquarePainter(hsv: _hsv),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              ),
              const SizedBox(height: 14),
              _HexField(
                controller: _hexCtrl,
                focusNode: _hexFocus,
                editing: _hexEditing,
                onChanged: (text) {
                  setState(() => _hexEditing = true);
                  _applyHex(text);
                },
              ),
              const SizedBox(height: 14),
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  widget.english ? 'Presets' : 'ألوان جاهزة',
                  style: const TextStyle(
                    color: HorseTheme.muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: .8,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final preset in _presets)
                    _PresetSwatch(
                      color: _parseHex(preset),
                      selected:
                          _hexOf(_hsv) == preset.toUpperCase(),
                      onTap: () => _update(
                          HSVColor.fromColor(_parseHex(preset))),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        Row(
          children: [
            // Live preview.
            Container(
              width: 44,
              height: 30,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: HorseTheme.line),
              ),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(widget.english ? 'Cancel' : 'إلغاء'),
            ),
            const SizedBox(width: 6),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: HorseTheme.gold,
                foregroundColor: const Color(0xFF1A1209),
              ),
              onPressed: () => Navigator.of(context).pop(_hexOf(_hsv)),
              child: Text(widget.english ? 'Select' : 'اختيار'),
            ),
          ],
        ),
      ],
    );
  }
}

// ── Painters ────────────────────────────────────────────────────────────────

class _WheelPainter extends CustomPainter {
  const _WheelPainter({required this.hsv});

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2 - 3;
    final midRadius = outerRadius - _kRingWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: midRadius);

    // Hue annulus — 180 thin arcs (±0.5° overlap avoids seams).
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _kRingWidth;
    const segments = 180;
    for (var i = 0; i < segments; i++) {
      final hue = i / segments * 360;
      arc.color = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
      canvas.drawArc(
        rect,
        (hue - 90) * math.pi / 180 - 0.5 * math.pi / 180,
        (360 / segments + 1) * math.pi / 180,
        false,
        arc,
      );
    }

    // Hue thumb.
    final angle = (hsv.hue - 90) * math.pi / 180;
    final thumbCenter =
        center + Offset(math.cos(angle), math.sin(angle)) * midRadius;
    canvas.drawCircle(
      thumbCenter,
      _kRingWidth / 2 - 1,
      Paint()..color = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor(),
    );
    canvas.drawCircle(
      thumbCenter,
      _kRingWidth / 2 - 1,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white,
    );
    canvas.drawCircle(
      thumbCenter,
      _kRingWidth / 2,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black38,
    );
  }

  @override
  bool shouldRepaint(_WheelPainter old) => old.hsv != hsv;
}

class _SquarePainter extends CustomPainter {
  const _SquarePainter({required this.hsv});

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final base = HSVColor.fromAHSV(1, hsv.hue, 1, 1).toColor();

    canvas.save();
    canvas.clipRect(rect);
    // Solid pure hue under everything.
    canvas.drawRect(rect, Paint()..color = base);
    // White → transparent horizontally (saturation axis).
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [Colors.white, Colors.transparent],
        ).createShader(rect),
    );
    // Transparent → black vertically (value axis).
    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
        ).createShader(rect),
    );
    canvas.restore();

    // Current color pointer.
    final pos = Offset(hsv.saturation * size.width, (1 - hsv.value) * size.height);
    canvas.drawCircle(pos, 7, Paint()..color = hsv.toColor());
    canvas.drawCircle(
      pos,
      8.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5
        ..color = Colors.white,
    );
    canvas.drawCircle(
      pos,
      9.5,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1
        ..color = Colors.black38,
    );
  }

  @override
  bool shouldRepaint(_SquarePainter old) => old.hsv != hsv;
}

// ── Pieces ──────────────────────────────────────────────────────────────────

class _HexField extends StatelessWidget {
  const _HexField({
    required this.controller,
    required this.focusNode,
    required this.editing,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool editing;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) => TextField(
        controller: controller,
        focusNode: focusNode,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.center,
        maxLength: 7,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
        ],
        style: const TextStyle(
          color: HorseTheme.ink,
          fontSize: 15,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
        ),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: HorseTheme.surface,
          hintText: '#RRGGBB',
          hintStyle: const TextStyle(color: Colors.white24, letterSpacing: 1.2),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
                color: editing ? HorseTheme.gold : HorseTheme.line),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: HorseTheme.gold, width: 1.4),
          ),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        ),
        onChanged: onChanged,
      );
}

class _PresetSwatch extends StatelessWidget {
  const _PresetSwatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? HorseTheme.ink : HorseTheme.line,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: selected
              ? Icon(Icons.check_rounded,
                  size: 15,
                  // Keep the check readable on light swatches too.
                  color: color.computeLuminance() > .6
                      ? Colors.black87
                      : Colors.white)
              : null,
        ),
      );
}
