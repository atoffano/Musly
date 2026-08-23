import 'package:dio/dio.dart';

import '../models/song.dart';
import 'subsonic_service.dart';

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

  factory SaveJobSnapshot.fromJson(Map<String, dynamic> json) {
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

  factory SaveResult.fromJson(Map<String, dynamic> json) {
    return SaveResult(
      jobId: json['jobId']?.toString() ?? '',
      status: json['status']?.toString() ?? 'failed',
      deduplicated: json['deduplicated'] as bool? ?? false,
    );
  }
}

class MuslyBackendService {
  final Dio _dio;

  MuslyBackendService({Dio? dio}) : _dio = dio ?? Dio() {
    _dio.options.connectTimeout = const Duration(seconds: 30);
    _dio.options.receiveTimeout = const Duration(seconds: 30);
  }

  Future<SearchResult> searchSongs(String baseUrl, String query) async {
    final response = await _dio.get(
      '$baseUrl/api/search',
      queryParameters: {'query': query},
    );
    final payload = response.data as Map<String, dynamic>;
    final songsJson = (payload['songs'] as List?) ?? const [];

    final songs = songsJson
        .map((raw) => Song.fromJson(raw as Map<String, dynamic>))
        .toList();

    return SearchResult(artists: const [], albums: const [], songs: songs);
  }

  Future<SearchResult> artistTopSongs(String baseUrl, String browseId) async {
    final response = await _dio.post(
      '$baseUrl/api/artist/top-songs',
      data: {'browseId': browseId},
    );
    final payload = response.data as Map<String, dynamic>;
    final songsJson = (payload['songs'] as List?) ?? const [];
    final songs = songsJson
        .map((raw) => Song.fromJson(raw as Map<String, dynamic>))
        .toList();
    return SearchResult(artists: const [], albums: const [], songs: songs);
  }

  Future<SearchResult> artistDiscography(String baseUrl, String browseId) async {
    final response = await _dio.post(
      '$baseUrl/api/artist/full-discography',
      data: {'browseId': browseId},
    );
    final payload = response.data as Map<String, dynamic>;
    final songsJson = (payload['songs'] as List?) ?? const [];
    final songs = songsJson
        .map((raw) => Song.fromJson(raw as Map<String, dynamic>))
        .toList();
    return SearchResult(artists: const [], albums: const [], songs: songs);
  }

  Future<String> resolveStreamUrl(String baseUrl, String videoId) async {
    final response = await _dio.post(
      '$baseUrl/api/stream',
      data: {'videoId': videoId},
    );
    final rawUrl = (response.data as Map<String, dynamic>)['streamUrl'] as String;
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
    return SaveResult.fromJson(response.data as Map<String, dynamic>);
  }

  Future<SaveJobSnapshot> getJobStatus(String baseUrl, String jobId) async {
    final response = await _dio.get('$baseUrl/api/job/$jobId');
    final payload = response.data as Map<String, dynamic>;
    final job = payload['job'] as Map<String, dynamic>;
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
    final payload = response.data as Map<String, dynamic>;
    return payload['status']?.toString() == 'removed';
  }

  Future<List<MoodSection>> getMoodCategories(String baseUrl) async {
    final response = await _dio.get('$baseUrl/api/moods');
    final payload = response.data as Map<String, dynamic>;
    final sectionsJson = (payload['sections'] as List?) ?? const [];
    return sectionsJson
        .map((raw) => MoodSection.fromJson(raw as Map<String, dynamic>))
        .toList();
  }

  Future<List<MoodPlaylist>> getMoodPlaylists(
    String baseUrl,
    String params,
  ) async {
    final response = await _dio.get(
      '$baseUrl/api/moods/$params',
    );
    final payload = response.data as Map<String, dynamic>;
    final playlistsJson = (payload['playlists'] as List?) ?? const [];
    return playlistsJson
        .map((raw) => MoodPlaylist.fromJson(raw as Map<String, dynamic>))
        .toList();
  }

  Future<List<MoodPlaylist>> getFeaturedPlaylists(String baseUrl) async {
    final response = await _dio.get('$baseUrl/api/featured-playlists');
    final payload = response.data as Map<String, dynamic>;
    final playlistsJson = (payload['playlists'] as List?) ?? const [];
    return playlistsJson
        .map((raw) => MoodPlaylist.fromJson(raw as Map<String, dynamic>))
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
    final payload = response.data as Map<String, dynamic>;
    final songsJson = (payload['songs'] as List?) ?? const [];
    return songsJson
        .map((raw) => Song.fromJson(raw as Map<String, dynamic>))
        .toList();
  }
}

class MoodSection {
  final String name;
  final List<MoodCategory> categories;

  MoodSection({required this.name, required this.categories});

  factory MoodSection.fromJson(Map<String, dynamic> json) {
    final cats = (json['categories'] as List?) ?? const [];
    return MoodSection(
      name: json['name'] as String? ?? '',
      categories: cats
          .map((c) => MoodCategory.fromJson(c as Map<String, dynamic>))
          .toList(),
    );
  }
}

class MoodCategory {
  final String params;
  final String title;

  MoodCategory({required this.params, required this.title});

  factory MoodCategory.fromJson(Map<String, dynamic> json) {
    return MoodCategory(
      params: json['params'] as String? ?? '',
      title: json['title'] as String? ?? '',
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

  factory MoodPlaylist.fromJson(Map<String, dynamic> json) {
    String? thumb;
    final thumbs = json['thumbnails'] as List?;
    if (thumbs != null && thumbs.isNotEmpty) {
      final last = thumbs.last as Map<String, dynamic>?;
      thumb = last?['url'] as String?;
    }
    return MoodPlaylist(
      playlistId: json['playlistId'] as String? ?? '',
      title: json['title'] as String? ?? '',
      description: json['description'] as String?,
      thumbnailUrl: thumb ?? json['thumbnailUrl'] as String?,
    );
  }
}

