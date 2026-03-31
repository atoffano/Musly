/// A lightweight artist reference parsed from Navidrome's `participants` field.
/// Standard Subsonic servers do not provide this field, so it is always optional.
class ArtistRef {
  final String id;
  final String name;

  const ArtistRef({required this.id, required this.name});

  factory ArtistRef.fromJson(Map<String, dynamic> json) {
    return ArtistRef(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name};

  static List<ArtistRef>? parseList(dynamic data) {
    if (data == null || data is! List) return null;
    final list = data
        .whereType<Map<String, dynamic>>()
        .map((e) => ArtistRef.fromJson(e))
        .where((a) => a.id.isNotEmpty || a.name.isNotEmpty)
        .toList();
    return list.isEmpty ? null : list;
  }
}
