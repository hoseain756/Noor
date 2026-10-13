import 'dart:convert';

import '../models/custom_list.dart';

const _prefix = 'hblist1.';

class SharedCustomList {
  const SharedCustomList({
    required this.name,
    required this.items,
    this.description,
  });

  final String name;
  final String? description;
  final List<CustomListItem> items;
}

String? encodeCustomListShare(CustomMediaList list) {
  try {
    final name = _limit(list.name.trim(), 80);
    if (name.isEmpty) return null;
    final items = list.items
        .where((item) => item.type == 'movie' || item.type == 'series')
        .take(300)
        .map((item) => {
              'id': _limit(item.id.trim(), 120),
              'type': item.type,
              'name': _limit(item.name.trim(), 200),
              if (item.poster != null) 'poster': _limit(item.poster!, 600),
            })
        .where((item) => item['id'] != '' && item['name'] != '')
        .toList();
    final description = _limit(list.description?.trim() ?? '', 200);
    final payload = <String, dynamic>{
      'n': name,
      if (description.isNotEmpty) 'd': description,
      'i': items,
    };
    final encoded = base64Url.encode(utf8.encode(jsonEncode(payload)));
    return _prefix + encoded.replaceAll('=', '');
  } catch (_) {
    return null;
  }
}

SharedCustomList? decodeCustomListShare(String input) {
  try {
    final marker = input.indexOf(_prefix);
    if (marker < 0) return null;
    final encoded = input
        .substring(marker + _prefix.length)
        .split(RegExp(r'[^A-Za-z0-9_\-=]'))
        .first;
    if (encoded.isEmpty) return null;
    final decoded = jsonDecode(utf8.decode(base64Url.decode(
      base64Url.normalize(encoded),
    )));
    if (decoded is! Map || decoded['i'] is! List) return null;
    final name = decoded['n'] is String
        ? _limit((decoded['n'] as String).trim(), 80)
        : '';
    if (name.isEmpty) return null;
    final description = decoded['d'] is String
        ? _limit((decoded['d'] as String).trim(), 200)
        : '';
    final items = <CustomListItem>[];
    final seen = <String>{};
    final now = DateTime.now().millisecondsSinceEpoch;
    for (final raw in (decoded['i'] as List).take(300)) {
      if (raw is! Map) continue;
      final id =
          raw['id'] is String ? _limit((raw['id'] as String).trim(), 120) : '';
      final title = raw['name'] is String
          ? _limit((raw['name'] as String).trim(), 200)
          : '';
      final type = raw['type']?.toString() ?? '';
      if (id.isEmpty ||
          title.isEmpty ||
          (type != 'movie' && type != 'series') ||
          !seen.add(id)) {
        continue;
      }
      final poster =
          raw['poster'] is String ? _limit(raw['poster'] as String, 600) : '';
      items.add(CustomListItem(
        id: id,
        type: type,
        name: title,
        poster: poster.isEmpty ? null : poster,
        addedAt: now,
      ));
    }
    return SharedCustomList(
      name: name,
      description: description.isEmpty ? null : description,
      items: items,
    );
  } catch (_) {
    return null;
  }
}

String _limit(String value, int max) =>
    value.length > max ? value.substring(0, max) : value;
