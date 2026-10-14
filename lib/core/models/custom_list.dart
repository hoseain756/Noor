class CustomListItem {
  const CustomListItem({
    required this.id,
    required this.type,
    required this.name,
    required this.addedAt,
    this.poster,
    this.releaseInfo,
    this.rating,
  });

  final String id;
  final String type;
  final String name;
  final int addedAt;
  final String? poster;
  final String? releaseInfo;
  final String? rating;

  factory CustomListItem.fromJson(Map<String, dynamic> json) => CustomListItem(
        id: (json['id'] ?? '').toString(),
        type: (json['type'] ?? 'movie').toString(),
        name: (json['name'] ?? '').toString(),
        poster: _optionalString(json['poster']),
        releaseInfo: _optionalString(json['releaseInfo']),
        rating: _optionalString(json['imdbRating'] ?? json['rating']),
        addedAt: (json['addedAt'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'type': type,
        'name': name,
        if (poster != null) 'poster': poster,
        if (releaseInfo != null) 'releaseInfo': releaseInfo,
        if (rating != null) 'imdbRating': rating,
        'addedAt': addedAt,
      };
}

class CustomMediaList {
  const CustomMediaList({
    required this.id,
    required this.name,
    required this.items,
    required this.createdAt,
    required this.updatedAt,
    this.description,
  });

  final String id;
  final String name;
  final String? description;
  final List<CustomListItem> items;
  final int createdAt;
  final int updatedAt;

  factory CustomMediaList.fromJson(Map<String, dynamic> json) =>
      CustomMediaList(
        id: (json['id'] ?? '').toString(),
        name: (json['name'] ?? '').toString(),
        description: _optionalString(json['description']),
        items: (json['items'] as List? ?? const [])
            .whereType<Map>()
            .map((row) =>
                CustomListItem.fromJson(Map<String, dynamic>.from(row)))
            .where((item) => item.id.isNotEmpty && item.name.isNotEmpty)
            .toList(),
        createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
        updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (description != null && description!.isNotEmpty)
          'description': description,
        'items': items.map((item) => item.toJson()).toList(),
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };
}

String? _optionalString(dynamic value) =>
    value is String && value.isNotEmpty ? value : null;
