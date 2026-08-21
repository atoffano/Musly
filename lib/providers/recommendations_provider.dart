import 'package:flutter/foundation.dart';
import '../models/song.dart';
import '../services/musly_backend_service.dart';

class RecommendationsProvider extends ChangeNotifier {
  final MuslyBackendService _backendService = MuslyBackendService();

  List<MoodSection> _sections = [];
  bool _loading = false;
  String? _error;
  bool _initialized = false;

  // Mood playlists state (when drilling into a category)
  List<MoodPlaylist> _moodPlaylists = [];
  bool _loadingPlaylists = false;
  String? _playlistsError;

  // Playlist songs state (when viewing songs inside a playlist)
  List<Song> _playlistSongs = [];
  bool _loadingSongs = false;
  String? _songsError;

  List<MoodSection> get sections => _sections;
  bool get loading => _loading;
  String? get error => _error;
  bool get initialized => _initialized;
  bool get hasData => _sections.isNotEmpty;

  List<MoodPlaylist> get moodPlaylists => _moodPlaylists;
  bool get loadingPlaylists => _loadingPlaylists;
  String? get playlistsError => _playlistsError;

  List<Song> get playlistSongs => _playlistSongs;
  bool get loadingSongs => _loadingSongs;
  String? get songsError => _songsError;

  Future<void> loadMoodCategories(String baseUrl) async {
    if (_loading) return;

    _loading = true;
    _error = null;
    notifyListeners();

    try {
      _sections = await _backendService.getMoodCategories(baseUrl);
      _initialized = true;
    } catch (e) {
      _error = e.toString();
      debugPrint('Failed to load mood categories: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> loadMoodPlaylists(String baseUrl, String params) async {
    if (_loadingPlaylists) return;

    _loadingPlaylists = true;
    _playlistsError = null;
    _moodPlaylists = [];
    notifyListeners();

    try {
      _moodPlaylists = await _backendService.getMoodPlaylists(baseUrl, params);
    } catch (e) {
      _playlistsError = e.toString();
      debugPrint('Failed to load mood playlists: $e');
    } finally {
      _loadingPlaylists = false;
      notifyListeners();
    }
  }

  Future<void> loadPlaylistSongs(
    String baseUrl,
    String playlistId, {
    int limit = 50,
  }) async {
    if (_loadingSongs) return;

    _loadingSongs = true;
    _songsError = null;
    _playlistSongs = [];
    notifyListeners();

    try {
      _playlistSongs = await _backendService.getPlaylistSongs(
        baseUrl,
        playlistId,
        limit: limit,
      );
    } catch (e) {
      _songsError = e.toString();
      debugPrint('Failed to load playlist songs: $e');
    } finally {
      _loadingSongs = false;
      notifyListeners();
    }
  }

  void clearPlaylists() {
    _moodPlaylists = [];
    _playlistsError = null;
    notifyListeners();
  }

  void clearSongs() {
    _playlistSongs = [];
    _songsError = null;
    notifyListeners();
  }
}
