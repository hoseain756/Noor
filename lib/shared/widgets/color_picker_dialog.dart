import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import '../../core/theme/nova_theme.dart';
import '../../l10n/nova_strings.dart';

/// Palette-first subtitle colour editor. Custom colours are user content.
Future<String?> showNoorColorPicker(BuildContext context,
        {required String initialHex, String? title, bool english = false}) =>
    showDialog<String>(
        context: context,
        builder: (_) => _NovaColorPicker(
            initialHex: initialHex, title: title, english: english));

class _NovaColorPicker extends StatefulWidget {
  const _NovaColorPicker(
      {required this.initialHex, this.title, required this.english});
  final String initialHex;
  final String? title;
  final bool english;
  @override
  State<_NovaColorPicker> createState() => _NovaColorPickerState();
}

class _NovaColorPickerState extends State<_NovaColorPicker> {
  late Color _color = _parse(widget.initialHex);
  late final _hex = TextEditingController(text: _hexOf(_color));
  String? _error;
  static const _presets = [
    NovaColors.white,
    NovaColors.ink,
    NovaColors.red,
    NovaColors.redSoft,
    NovaColors.mist,
    NovaColors.blush,
    NovaColors.success,
    NovaColors.warning,
    NovaColors.info,
    NovaColors.rating
  ];
  static Color _parse(String raw) => Color(0xFF000000 |
      (int.tryParse(raw.replaceAll('#', ''), radix: 16) ?? 0xFFFFFF));
  static String _hexOf(Color color) =>
      '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
  void _select(Color color) => setState(() {
        _color = color;
        _hex.text = _hexOf(color);
        _error = null;
      });
  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final english = widget.english;
    final s = NovaStrings.of(context);
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: Text(widget.title ?? (NovaStrings.lookup(english, 'message724'))),
      content: SizedBox(
          width: 400,
          child: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                        color: NovaColors.ink,
                        borderRadius: BorderRadius.circular(16)),
                    child: Text(NovaStrings.lookup(english, 'message725'),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: _color,
                            fontSize: 20,
                            fontWeight: FontWeight.w600))),
                const SizedBox(height: 24),
                Wrap(spacing: 12, runSpacing: 12, children: [
                  for (final color in _presets)
                    Semantics(
                        button: true,
                        selected: color == _color,
                        label: _hexOf(color),
                        child: Tooltip(
                            message: _hexOf(color),
                            child: InkWell(
                                onTap: () => _select(color),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                    width: 48,
                                    height: 48,
                                    decoration: BoxDecoration(
                                        color: color,
                                        borderRadius: BorderRadius.circular(12),
                                        border:
                                            Border.all(color: scheme.outline)),
                                    child: color == _color
                                        ? Icon(LucideIcons.check,
                                            color: color.computeLuminance() > .4
                                                ? NovaColors.ink
                                                : NovaColors.white)
                                        : null))))
                ]),
                const SizedBox(height: 24),
                TextField(
                    controller: _hex,
                    textDirection: TextDirection.ltr,
                    inputFormatters: [LengthLimitingTextInputFormatter(7)],
                    decoration: InputDecoration(
                        labelText: NovaStrings.lookup(english, 'message726'),
                        errorText: _error),
                    onChanged: (value) {
                      if (RegExp(r'^#?[0-9a-fA-F]{6}$').hasMatch(value)) {
                        setState(() {
                          _color = _parse(value);
                          _error = null;
                        });
                      } else {
                        setState(() =>
                            _error = NovaStrings.lookup(english, 'message727'));
                      }
                    }),
              ]))),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(s.text('cancel'))),
        FilledButton(
            onPressed: _error == null
                ? () => Navigator.pop(context, _hexOf(_color))
                : null,
            child: Text(s.text('save')))
      ],
    );
  }
}
