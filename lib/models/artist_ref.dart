/// A lightweight artist reference parsed from Navidrome's `participants` field.
/// Standard Subsonic servers do not provide this field, so it is always optional.
class ArtistRef {
  final String id;
  final String name;
  /// Explicit cover art ID from the API response. When absent, falls back to
  /// [id] for servers (like Navidrome) that serve artist images via
  /// `getCoverArt?id={artistId}`.
  final String? coverArt;

  const ArtistRef({required this.id, required this.name, this.coverArt});

  /// Cover art ID for `getCoverArt`: explicit [coverArt] if set, otherwise [id].
  String? get effectiveCoverArt {
    if (coverArt != null && coverArt!.isNotEmpty) return coverArt;
    return id.isNotEmpty ? id : null;
  }

  factory ArtistRef.fromJson(Map<String, dynamic> json) {
    return ArtistRef(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      coverArt: json['coverArt']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    if (coverArt != null) 'coverArt': coverArt,
  };

  static List<ArtistRef>? parseList(dynamic data) {
    if (data == null || data is! List) return null;
    final list = data
        .whereType<Map>()
        .map((e) => ArtistRef.fromJson(
            e is Map<String, dynamic> ? e : Map<String, dynamic>.from(e)))
        .where((a) => a.id.isNotEmpty || a.name.isNotEmpty)
        .toList();
    return list.isEmpty ? null : list;
  }

  /// Splits a composite artist string (e.g. "Artist A & Artist B", "A feat. B")
  /// into individual ArtistRef items.
  static List<ArtistRef> splitArtistString(String raw, [String? idFallback]) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return const [];

    final regex = RegExp(
      r'\s*(?:,\s*|\s+&\s+|\s+and\s+|\s+feat\.?\s+|\s+ft\.?\s+|\s+featuring\s+|\s+\/\s+|\s+vs\.?\s+|\s+[xX]\s+|\s+with\s+)\s*',
      caseSensitive: false,
    );

    final parts = trimmed
        .split(regex)
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();

    if (parts.length <= 1) {
      return [ArtistRef(id: idFallback ?? '', name: trimmed)];
    }

    return parts.map((name) => ArtistRef(id: '', name: name)).toList();
  }
}

