class IptvChannel {
  const IptvChannel({
    required this.name,
    required this.url,
    this.logo,
    this.group,
    this.tvgId,
  });

  final String name;
  final String url;
  final String? logo;
  final String? group;
  final String? tvgId;
}

class IptvProgram {
  const IptvProgram({
    required this.title,
    required this.start,
    required this.stop,
    this.description,
  });

  final String title;
  final DateTime start;
  final DateTime stop;
  final String? description;
}

List<IptvChannel> parseM3u(String text) {
  final channels = <IptvChannel>[];
  final lines = text.replaceFirst('\uFEFF', '').split(RegExp(r'\r?\n'));
  Map<String, String>? pending;

  for (final raw in lines) {
    final line = raw.trim();
    if (line.startsWith('#EXTINF')) {
      final comma = line.indexOf(',');
      final metadata = comma < 0 ? line : line.substring(0, comma);
      final name = comma < 0 ? '' : line.substring(comma + 1).trim();
      pending = {
        'name': name.isEmpty ? 'Unknown channel' : name,
        'tvgId': _m3uAttribute(metadata, 'tvg-id') ?? '',
        'logo': _m3uAttribute(metadata, 'tvg-logo') ?? '',
        'group': _m3uAttribute(metadata, 'group-title') ?? '',
      };
      continue;
    }
    if (pending != null && line.startsWith('#EXTGRP:')) {
      final group = line.substring('#EXTGRP:'.length).trim();
      if (group.isNotEmpty) pending['group'] = group;
      continue;
    }
    if (line.isEmpty || line.startsWith('#')) continue;

    if (pending != null && _isSupportedChannelUrl(line)) {
      channels.add(
        IptvChannel(
          name: pending['name'] ?? 'Unknown channel',
          url: line,
          tvgId: _nonEmpty(pending['tvgId']),
          logo: _nonEmpty(pending['logo']),
          group: _nonEmpty(pending['group']),
        ),
      );
    }
    pending = null;
  }
  return channels;
}

Map<String, List<IptvProgram>> parseXmltv(String text) {
  final result = <String, List<IptvProgram>>{};
  final programPattern = RegExp(
    r'<programme\b([^>]*)>([\s\S]*?)</programme\s*>',
    caseSensitive: false,
  );
  for (final match in programPattern.allMatches(text)) {
    final attributes = _xmlAttributes(match.group(1) ?? '');
    final channel = attributes['channel']?.trim() ?? '';
    final start = parseXmltvTime(attributes['start'] ?? '');
    final stop = parseXmltvTime(attributes['stop'] ?? '');
    final body = match.group(2) ?? '';
    final title = _xmlElementText(body, 'title');
    if (channel.isEmpty || title.isEmpty || start == null || stop == null) {
      continue;
    }
    result.putIfAbsent(channel, () => []).add(
          IptvProgram(
            title: title,
            start: start,
            stop: stop,
            description: _nonEmpty(_xmlElementText(body, 'desc')),
          ),
        );
  }
  for (final programs in result.values) {
    programs.sort((a, b) => a.start.compareTo(b.start));
  }
  return result;
}

DateTime? parseXmltvTime(String value) {
  final match = RegExp(
    r'^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})?\s*([+-]\d{4})?$',
  ).firstMatch(value.trim());
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  final hour = int.parse(match.group(4)!);
  final minute = int.parse(match.group(5)!);
  final second = int.tryParse(match.group(6) ?? '') ?? 0;
  final utc = DateTime.utc(year, month, day, hour, minute, second);
  final offset = match.group(7);
  if (offset == null) return utc;
  final sign = offset.startsWith('-') ? -1 : 1;
  final hours = int.parse(offset.substring(1, 3));
  final minutes = int.parse(offset.substring(3, 5));
  return utc.subtract(Duration(minutes: sign * (hours * 60 + minutes)));
}

bool _isSupportedChannelUrl(String value) {
  final uri = Uri.tryParse(value);
  return uri != null &&
      uri.hasAuthority &&
      (uri.scheme == 'http' || uri.scheme == 'https');
}

String? _m3uAttribute(String text, String name) {
  final escaped = RegExp.escape(name);
  final match = RegExp(
    '$escaped\\s*=\\s*' r'''(?:"([^"]*)"|'([^']*)'|([^\s]+))''',
    caseSensitive: false,
  ).firstMatch(text);
  return _nonEmpty(match?.group(1) ?? match?.group(2) ?? match?.group(3));
}

Map<String, String> _xmlAttributes(String text) {
  final result = <String, String>{};
  final pattern = RegExp(r'''([\w:-]+)\s*=\s*(?:"([^"]*)"|'([^']*)')''');
  for (final match in pattern.allMatches(text)) {
    result[match.group(1)!] =
        _decodeXml(match.group(2) ?? match.group(3) ?? '');
  }
  return result;
}

String _xmlElementText(String body, String name) {
  final pattern = RegExp(
    '<$name(?:\\s[^>]*)?>([\\s\\S]*?)</$name\\s*>',
    caseSensitive: false,
  );
  final raw = pattern.firstMatch(body)?.group(1)?.trim() ?? '';
  final cdata = RegExp(r'^<!\[CDATA\[([\s\S]*)\]\]>$').firstMatch(raw);
  return _decodeXml(cdata?.group(1) ?? raw).trim();
}

String _decodeXml(String value) => value.replaceAllMapped(
      RegExp(r'&(#x[0-9a-f]+|#\d+|amp|lt|gt|quot|apos);', caseSensitive: false),
      (match) {
        final entity = match.group(1)!;
        if (entity.startsWith('#x')) {
          return String.fromCharCode(
              int.tryParse(entity.substring(2), radix: 16) ?? 0xFFFD);
        }
        if (entity.startsWith('#')) {
          return String.fromCharCode(
              int.tryParse(entity.substring(1)) ?? 0xFFFD);
        }
        return switch (entity.toLowerCase()) {
          'amp' => '&',
          'lt' => '<',
          'gt' => '>',
          'quot' => '"',
          'apos' => "'",
          _ => match.group(0)!,
        };
      },
    );

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}
