import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:musly/services/musly_backend_service.dart';

class _FakeAdapter implements HttpClientAdapter {
  final Map<String, dynamic> Function(RequestOptions options) resolver;

  _FakeAdapter(this.resolver);

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<List<int>>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final data = resolver(options);
    return ResponseBody.fromString(
      data is String ? data : jsonEncode(data),
      200,
      headers: {Headers.contentTypeHeader: ['application/json']},
    );
  }
}

void main() {
  test('searchSongs should parse YouTube song payload', () async {
    final dio = Dio();
    dio.httpClientAdapter = _FakeAdapter((options) {
      if (options.path.endsWith('/api/search')) {
        return {
          'songs': [
            {
              'id': 'yt:dQw4w9WgXcQ',
              'title': 'Never Gonna Give You Up',
              'artist': 'Rick Astley',
              'sourceType': 'youtube',
              'sourceId': 'dQw4w9WgXcQ',
              'saved': false,
            }
          ]
        };
      }
      return {};
    });

    final service = MuslyBackendService(dio: dio);
    final result = await service.searchSongs('http://localhost:8788', 'Never gonna give you up');

    expect(result.songs.length, 1);
    expect(result.songs.first.id, 'yt:dQw4w9WgXcQ');
    expect(result.songs.first.isYouTube, true);
  });
}
