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
    return (response.data as Map<String, dynamic>)['streamUrl'] as String;
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
}
