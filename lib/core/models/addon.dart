class AddonCatalog {
  const AddonCatalog({
    required this.id,
    required this.type,
    required this.name,
    this.extra = const [],
  });

  final String id;
  final String type;
  final String name;
  final List<Map<String, dynamic>> extra;

  factory AddonCatalog.fromJson(Map<String, dynamic> json) => AddonCatalog(
        id: (json['id'] ?? '').toString(),
        type: (json['type'] ?? 'movie').toString(),
        name: (json['name'] ?? json['id'] ?? 'Catalog').toString(),
        extra: (json['extra'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'name': name,
        if (extra.isNotEmpty) 'extra': extra,
      };
}

class Addon {
  const Addon({
    required this.id,
    required this.name,
    required this.transportUrl,
    required this.manifest,
    this.enabled = true,
    this.order = 0,
  });

  final String id;
  final String name;
  final String transportUrl;
  final Map<String, dynamic> manifest;
  final bool enabled;
  final int order;

  List<AddonCatalog> get catalogs => (manifest['catalogs'] as List? ?? const [])
      .whereType<Map>()
      .map((e) => AddonCatalog.fromJson(Map<String, dynamic>.from(e)))
      .where((e) => e.id.isNotEmpty)
      .toList();

  String get baseUrl => transportUrl
      .replaceFirst(RegExp(r'/manifest\.json.*$'), '')
      .replaceFirst(RegExp(r'/+$'), '');

  /// The add-on's own icon URL from the manifest (Task 123): shown in the
  /// sources page rows/picker. Null unless a well-formed http(s) URL.
  String? get iconUrl {
    final value = manifest['icon']?.toString() ?? '';
    if (value.isEmpty) return null;
    return value.startsWith('http://') || value.startsWith('https://')
        ? value
        : null;
  }

  bool supports(String resource, String type, String id) {
    final resources = (manifest['resources'] as List? ?? const []);
    final resourceMatch = resources.any((entry) {
      if (entry is String) return entry == resource;
      if (entry is! Map || entry['name'] != resource) return false;
      final types =
          (entry['types'] as List? ?? manifest['types'] as List? ?? const [])
              .map((e) => e.toString());
      final prefixes = (entry['idPrefixes'] as List? ??
              manifest['idPrefixes'] as List? ??
              const [])
          .map((e) => e.toString());
      return (types.isEmpty || types.contains(type)) &&
          (prefixes.isEmpty || prefixes.any(id.startsWith));
    });
    if (resourceMatch) return true;
    return resource == 'catalog' && catalogs.any((c) => c.type == type);
  }

  factory Addon.fromJson(Map<String, dynamic> json) {
    final manifest = Map<String, dynamic>.from(
      json['manifest'] as Map? ?? const {},
    );
    return Addon(
      id: (manifest['id'] ?? json['id'] ?? '').toString(),
      name: (manifest['name'] ?? json['name'] ?? 'Addon').toString(),
      transportUrl: (json['transportUrl'] ?? json['url'] ?? '').toString(),
      manifest: manifest,
      enabled: json['enabled'] != false,
      order: (json['order'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() => {
        'transportUrl': transportUrl,
        'enabled': enabled,
        'order': order,
        'manifest': manifest,
      };

  Addon copyWith({bool? enabled, int? order}) => Addon(
        id: id,
        name: name,
        transportUrl: transportUrl,
        manifest: manifest,
        enabled: enabled ?? this.enabled,
        order: order ?? this.order,
      );
}
