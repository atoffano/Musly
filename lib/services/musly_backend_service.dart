import 'dart:convert';
import 'package:dio/dio.dart';

import '../models/song.dart';
import 'subsonic_service.dart';

Map<String, dynamic> _toMap(dynamic data) {
  if (data == null) return {};
  if (data is Map<String, dynamic>) return data;
  if (data is Map) {
    return data.map((key, value) => MapEntry(key.toString(), value));
  }
  if (data is String) {
    try {
      final decoded = json.decode(data);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
  }
  return {};
}

class SaveJobSnapshot {
  final String jobId;
  final String videoId;
  final String status;
  final String? errorCode;
  final String? errorMessage;

  SaveJobSnapshot({
    required this.jobId,
    required this.videoId,
    required this.status,
    this.errorCode,
    this.errorMessage,
  });

  factory SaveJobSnapshot.fromJson(Map<dynamic, dynamic> json) {
    return SaveJobSnapshot(
      jobId: json['jobId']?.toString() ?? '',
      videoId: json['videoId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'failed',
      errorCode: json['errorCode']?.toString(),
      errorMessage: json['errorMessage']?.toString(),
    );
  }
}

class SaveResult {
  final String jobId;
  final String status;
  final bool deduplicated;

  SaveResult({
    required this.jobId,
    required this.status,
    required this.deduplicated,
  });

  factory SaveResult.fromJson(Map<dynamic, dynamic> json) {
    return SaveResult(
      jobId: json['jobId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'failed',
      deduplicated: json['deduplicated'] == true,
    );
  }
}

class MuslyBackendService {
  final Dio _dio;
  static MuslyBackendService? _instance;

  factory MuslyBackendService({Dio? dio}) {
    if (dio != null) {
      return MuslyBackendService._internal(dio);
    }
    return _instance ??= MuslyBackendService._internal(Dio());
  }

  MuslyBackendService._internal(Dio dio) : _dio = dio {
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }


  Future<SearchResult> searchSongs(String baseUrl, String query) async {
    final response = await _dio.get(
      '$baseUrl/api/search',
      queryParameters: {'query': query},
    );
    final payload = _toMap(response.data);
    final songsJson = (payload['songs'] as List?) ?? const [];

    final songs = songsJson
        .whereType<Map>()
        .map((raw) => Song.fromJson(_toMap(raw)))
        .toList();

    return SearchResult(artists: const [], albums: const [], songs: songs);
  }

  Future<SearchResult> artistTopSongs(String baseUrl, String browseId) async {
    final response = await _dio.post(
      '$baseUrl/api/artist/top-songs',
      data: {'browseId': browseId},
    );
    final payload = _toMap(response.data);
    final songsJson = (payload['songs'] as List?) ?? const [];
    final songs = songsJson
        .whereType<Map>()
        .map((raw) => Song.fromJson(_toMap(raw)))
        .toList();
    return SearchResult(artists: const [], albums: const [], songs: songs);
  }

  Future<SearchResult> artistDiscography(String baseUrl, String browseId) async {
    final response = await _dio.post(
      '$baseUrl/api/artist/full-discography',
      data: {'browseId': browseId},
    );
    final payload = _toMap(response.data);
    final songsJson = (payload['songs'] as List?) ?? const [];
    final songs = songsJson
        .whereType<Map>()
        .map((raw) => Song.fromJson(_toMap(raw)))
        .toList();
    return SearchResult(artists: const [], albums: const [], songs: songs);
  }

  Future<String> resolveStreamUrl(String baseUrl, String videoId) async {
    final response = await _dio.post(
      '$baseUrl/api/stream',
      data: {'videoId': videoId},
    );
    final payload = _toMap(response.data);
    final rawUrl = payload['streamUrl']?.toString() ?? '';
    if (rawUrl.startsWith('http://') || rawUrl.startsWith('https://')) {
      return rawUrl;
    }
    final cleanBase = baseUrl.endsWith('/') ? baseUrl.substring(0, baseUrl.length - 1) : baseUrl;
    final cleanPath = rawUrl.startsWith('/') ? rawUrl : '/$rawUrl';
    return '$cleanBase$cleanPath';
  }

  Future<SaveResult> saveSong(
    String baseUrl, {
    required String videoId,
    String? title,
    String? artist,
    String? album,
  }) async {
    final response = await _dio.post(
      '$baseUrl/api/save',
      data: {
        'videoId': videoId,
        if (title != null) 'title': title,
        if (artist != null) 'artist': artist,
        if (album != null) 'album': album,
      },
    );
    return SaveResult.fromJson(_toMap(response.data));
  }

  Future<SaveJobSnapshot> getJobStatus(String baseUrl, String jobId) async {
    final response = await _dio.get('$baseUrl/api/job/$jobId');
    final payload = _toMap(response.data);
    final job = _toMap(payload['job']);
    return SaveJobSnapshot.fromJson(job);
  }

  Future<bool> deleteSong(
    String baseUrl,
    String videoId, {
    String? songId,
  }) async {
    final response = await _dio.post(
      '$baseUrl/api/delete',
      data: {
        if (videoId.isNotEmpty) 'videoId': videoId,
        if (songId != null && songId.isNotEmpty) 'songId': songId,
      },
    );
    final payload = _toMap(response.data);
    return payload['status']?.toString() == 'removed';
  }

  Future<List<MoodSection>> getMoodCategories(String baseUrl) async {
    final response = await _dio.get('$baseUrl/api/moods');
    final payload = _toMap(response.data);
    final sectionsJson = (payload['sections'] as List?) ?? const [];
    return sectionsJson
        .whereType<Map>()
        .map((raw) => MoodSection.fromJson(_toMap(raw)))
        .toList();
  }

  Future<List<MoodPlaylist>> getMoodPlaylists(
    String baseUrl,
    String params,
  ) async {
    final response = await _dio.get(
      '$baseUrl/api/moods/$params',
    );
    final payload = _toMap(response.data);
    final playlistsJson = (payload['playlists'] as List?) ?? const [];
    return playlistsJson
        .whereType<Map>()
        .map((raw) => MoodPlaylist.fromJson(_toMap(raw)))
        .toList();
  }

  Future<List<MoodPlaylist>> getFeaturedPlaylists(String baseUrl) async {
    final response = await _dio.get('$baseUrl/api/featured-playlists');
    final payload = _toMap(response.data);
    final playlistsJson = (payload['playlists'] as List?) ?? const [];
    return playlistsJson
        .whereType<Map>()
        .map((raw) => MoodPlaylist.fromJson(_toMap(raw)))
        .toList();
  }

  Future<List<Song>> getPlaylistSongs(
    String baseUrl,
    String playlistId, {
    int limit = 50,
  }) async {
    final response = await _dio.post(
      '$baseUrl/api/playlist-songs',
      data: {'playlistId': playlistId, 'limit': limit},
    );
    final payload = _toMap(response.data);
    final songsJson = (payload['songs'] as List?) ?? const [];
    return songsJson
        .whereType<Map>()
        .map((raw) => Song.fromJson(_toMap(raw)))
        .toList();
  }
}

class MoodSection {
  final String name;
  final List<MoodCategory> categories;

  MoodSection({required this.name, required this.categories});

  factory MoodSection.fromJson(Map<dynamic, dynamic> json) {
    final cats = (json['categories'] as List?) ?? const [];
    return MoodSection(
      name: json['name']?.toString() ?? '',
      categories: cats
          .whereType<Map>()
          .map((c) => MoodCategory.fromJson(c))
          .toList(),
    );
  }
}

class MoodCategory {
  final String params;
  final String title;

  MoodCategory({required this.params, required this.title});

  factory MoodCategory.fromJson(Map<dynamic, dynamic> json) {
    return MoodCategory(
      params: json['params']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
    );
  }
}

class MoodPlaylist {
  final String playlistId;
  final String title;
  final String? description;
  final String? thumbnailUrl;

  MoodPlaylist({
    required this.playlistId,
    required this.title,
    this.description,
    this.thumbnailUrl,
  });

  factory MoodPlaylist.fromJson(Map<dynamic, dynamic> json) {
    String? thumb;
    final thumbs = json['thumbnails'] as List?;
    if (thumbs != null && thumbs.isNotEmpty) {
      final last = thumbs.last;
      if (last is Map) {
        thumb = last['url']?.toString();
      }
    }
    return MoodPlaylist(
      playlistId: json['playlistId']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      description: json['description']?.toString(),
      thumbnailUrl: thumb ?? json['thumbnailUrl']?.toString(),
    );
  }
}


