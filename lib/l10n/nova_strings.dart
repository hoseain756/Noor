import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'nova_messages.g.dart';

/// ARB is the source of truth. Run `python tool/generate_nova_l10n.py` after edits.
class NovaStrings {
  const NovaStrings(this.locale);
  final Locale locale;
  bool get english => locale.languageCode != 'ar';
  static NovaStrings of(BuildContext context) =>
      Localizations.of<NovaStrings>(context, NovaStrings) ??
      NovaStrings(Localizations.maybeLocaleOf(context) ?? const Locale('en'));
  static const delegate = _NovaDelegate();
  String text(String key, [Map<String, Object?> args = const {}]) {
    var result =
        (english ? novaEnglish : novaArabic)[key] ?? novaEnglish[key] ?? key;
    for (final entry in args.entries) {
      result = result.replaceAll('{${entry.key}}', '${entry.value ?? ''}');
    }
    return result;
  }

  static String lookup(bool english, String key,
          [Map<String, Object?> args = const {}]) =>
      NovaStrings(Locale(english ? 'en' : 'ar')).text(key, args);
}

class _NovaDelegate extends LocalizationsDelegate<NovaStrings> {
  const _NovaDelegate();
  @override
  bool isSupported(Locale locale) => ['en', 'ar'].contains(locale.languageCode);
  @override
  Future<NovaStrings> load(Locale locale) =>
      SynchronousFuture(NovaStrings(locale));
  @override
  bool shouldReload(_NovaDelegate old) => false;
}
