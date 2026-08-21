import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/player_provider.dart';
import '../providers/recommendations_provider.dart';
import '../services/musly_backend_service.dart';
import '../services/subsonic_service.dart';
import '../services/storage_service.dart';
import '../models/song.dart';
import '../theme/app_theme.dart';
import '../widgets/widgets.dart';
import '../l10n/app_localizations.dart';

/// Main entry screen – shows YT Music mood/genre categories.
class RecommendationsScreen extends StatefulWidget {
  const RecommendationsScreen({super.key});

  @override
  State<RecommendationsScreen> createState() => _RecommendationsScreenState();
}

class _RecommendationsScreenState extends State<RecommendationsScreen> {
  String? _bridgeUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCategories();
    });
  }

  String? _resolveBridgeUrl() {
    if (_bridgeUrl != null && _bridgeUrl!.isNotEmpty) return _bridgeUrl;
    try {
      final config = Provider.of<SubsonicService>(context, listen: false).config;
      return config?.bridgeUrl;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadCategories() async {
    final directUrl = _resolveBridgeUrl();
    if (directUrl != null && directUrl.isNotEmpty) {
      if (mounted) setState(() => _bridgeUrl = directUrl);
      final recProvider =
          Provider.of<RecommendationsProvider>(context, listen: false);
      if (!recProvider.initialized) {
        await recProvider.loadMoodCategories(directUrl);
      }
      return;
    }

    final storageService = Provider.of<StorageService>(context, listen: false);
    final settings = await storageService.getServerConfig();
    final url = settings?.bridgeUrl;

    if (mounted) {
      setState(() => _bridgeUrl = url);
    }

    if (url == null || url.isEmpty) return;

    final recProvider =
        Provider.of<RecommendationsProvider>(context, listen: false);
    if (!recProvider.initialized) {
      await recProvider.loadMoodCategories(url);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context);
    final effectiveBridgeUrl = _bridgeUrl ?? _resolveBridgeUrl() ?? '';

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: Text(
              l10n?.recommendations ?? 'Recommendations',
            ),
            actions: [
              IconButton(
                icon: const Icon(CupertinoIcons.refresh),
                onPressed: effectiveBridgeUrl.isNotEmpty
                    ? () {
                        final recProvider =
                            Provider.of<RecommendationsProvider>(
                                context,
                                listen: false);
                        recProvider.loadMoodCategories(effectiveBridgeUrl);
                      }
                    : null,
                tooltip: 'Refresh',
              ),
            ],
          ),
          Consumer<RecommendationsProvider>(
            builder: (context, recProvider, _) {
              if (recProvider.loading) {
                return SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: List.generate(
                        8,
                        (_) => Container(
                          width: 160,
                          height: 90,
                          decoration: BoxDecoration(
                            color: isDark
                                ? const Color(0xFF282828)
                                : Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }

              if (recProvider.error != null) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline,
                            size: 64, color: AppTheme.lightSecondaryText),
                        const SizedBox(height: 16),
                        Text('Error loading categories',
                            style: theme.textTheme.headlineSmall),
                        const SizedBox(height: 8),
                        Text(recProvider.error ?? '',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: AppTheme.lightSecondaryText),
                            textAlign: TextAlign.center),
                        const SizedBox(height: 24),
                        ElevatedButton.icon(
                          onPressed: effectiveBridgeUrl.isNotEmpty
                              ? () =>
                                  recProvider.loadMoodCategories(effectiveBridgeUrl)
                              : null,
                          icon: const Icon(Icons.refresh),
                          label: Text(l10n?.retry ?? 'Try again'),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (!recProvider.hasData) {
                return SliverFillRemaining(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.explore,
                            size: 64, color: AppTheme.lightSecondaryText),
                        const SizedBox(height: 16),
                        Text('No categories found',
                            style: theme.textTheme.headlineSmall),
                      ],
                    ),
                  ),
                );
              }

              // Build sections of mood categories
              return SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    if (index >= recProvider.sections.length) {
                      return const SizedBox(height: 120);
                    }
                    final section = recProvider.sections[index];
                    return _MoodSectionWidget(
                      section: section,
                      bridgeUrl: effectiveBridgeUrl,
                      isDark: isDark,
                    );
                  },
                  childCount: recProvider.sections.length + 1,
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _MoodSectionWidget extends StatelessWidget {
  final MoodSection section;
  final String bridgeUrl;
  final bool isDark;

  const _MoodSectionWidget({
    required this.section,
    required this.bridgeUrl,
    required this.isDark,
  });

  static const _sectionGradients = <String, List<Color>>{
    'For you': [Color(0xFF8B5CF6), Color(0xFFEC4899)],
    'Genres': [Color(0xFF10B981), Color(0xFF06B6D4)],
    'Moods & moments': [Color(0xFFF59E0B), Color(0xFFEF4444)],
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 12),
          child: Text(
            section.name,
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SizedBox(
          height: 100,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: section.categories.length,
            itemBuilder: (context, index) {
              final cat = section.categories[index];
              final gradientColors = _sectionGradients[section.name] ??
                  [Colors.blue, Colors.indigo];
              // Rotate hue slightly per card for visual variety
              final hueShift = (index * 15.0) % 360;
              final color1 = HSLColor.fromColor(gradientColors[0])
                  .withHue(
                      (HSLColor.fromColor(gradientColors[0]).hue + hueShift) %
                          360)
                  .toColor();
              final color2 = HSLColor.fromColor(gradientColors[1])
                  .withHue(
                      (HSLColor.fromColor(gradientColors[1]).hue + hueShift) %
                          360)
                  .toColor();

              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: SizedBox(
                  width: 140,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => _MoodPlaylistsScreen(
                              categoryTitle: cat.title,
                              categoryParams: cat.params,
                              bridgeUrl: bridgeUrl,
                            ),
                          ),
                        );
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [color1, color2],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.all(12),
                        child: Align(
                          alignment: Alignment.bottomLeft,
                          child: Text(
                            cat.title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Second-level screen – playlists for a mood/genre category.
class _MoodPlaylistsScreen extends StatefulWidget {
  final String categoryTitle;
  final String categoryParams;
  final String bridgeUrl;

  const _MoodPlaylistsScreen({
    required this.categoryTitle,
    required this.categoryParams,
    required this.bridgeUrl,
  });

  @override
  State<_MoodPlaylistsScreen> createState() => _MoodPlaylistsScreenState();
}

class _MoodPlaylistsScreenState extends State<_MoodPlaylistsScreen> {
  final MuslyBackendService _backend = MuslyBackendService();
  List<MoodPlaylist> _playlists = [];
  bool _isLoading = true;
  String? _error;

  String _getEffectiveBridgeUrl() {
    if (widget.bridgeUrl.isNotEmpty) return widget.bridgeUrl;
    try {
      final config = Provider.of<SubsonicService>(context, listen: false).config;
      return config?.bridgeUrl ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    final bridgeUrl = _getEffectiveBridgeUrl();
    if (bridgeUrl.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'Bridge server unavailable';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _playlists = await _backend.getMoodPlaylists(
        bridgeUrl,
        widget.categoryParams,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final effectiveBridgeUrl = _getEffectiveBridgeUrl();

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            title: Text(widget.categoryTitle),
          ),
          if (_isLoading)
            SliverToBoxAdapter(
              child: Column(
                children: List.generate(8, (_) => const SongTileShimmer()),
              ),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline,
                        size: 64, color: AppTheme.lightSecondaryText),
                    const SizedBox(height: 16),
                    Text('Error loading playlists',
                        style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _loadPlaylists,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          else if (_playlists.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text('No playlists found',
                    style: theme.textTheme.headlineSmall),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index >= _playlists.length) {
                    return const SizedBox(height: 120);
                  }
                  final playlist = _playlists[index];
                  return _PlaylistTile(
                    playlist: playlist,
                    isDark: isDark,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => _PlaylistSongsScreen(
                            playlistTitle: playlist.title,
                            playlistId: playlist.playlistId,
                            bridgeUrl: effectiveBridgeUrl,
                            thumbnailUrl: playlist.thumbnailUrl,
                          ),
                        ),
                      );
                    },
                  );
                },
                childCount: _playlists.length + 1,
              ),
            ),
        ],
      ),
    );
  }
}

class _PlaylistTile extends StatelessWidget {
  final MoodPlaylist playlist;
  final bool isDark;
  final VoidCallback onTap;

  const _PlaylistTile({
    required this.playlist,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 56,
                height: 56,
                child: playlist.thumbnailUrl != null
                    ? CachedNetworkImage(
                        imageUrl: playlist.thumbnailUrl!,
                        fit: BoxFit.cover,
                        placeholder: (_, __) =>
                            Container(color: Colors.grey[800]),
                        errorWidget: (_, __, ___) => Container(
                          color: isDark
                              ? const Color(0xFF282828)
                              : Colors.grey[300],
                          child: const Icon(Icons.music_note,
                              color: Colors.white54),
                        ),
                      )
                    : Container(
                        color: isDark
                            ? const Color(0xFF282828)
                            : Colors.grey[300],
                        child:
                            const Icon(Icons.music_note, color: Colors.white54),
                      ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    playlist.title,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (playlist.description != null &&
                      playlist.description!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        playlist.description!,
                        style: TextStyle(
                          color: isDark ? Colors.white60 : Colors.black54,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              CupertinoIcons.chevron_right,
              size: 16,
              color: isDark ? Colors.white38 : Colors.black38,
            ),
          ],
        ),
      ),
    );
  }
}

/// Third-level screen – streamable, saveable songs from a YT playlist.
class _PlaylistSongsScreen extends StatefulWidget {
  final String playlistTitle;
  final String playlistId;
  final String bridgeUrl;
  final String? thumbnailUrl;

  const _PlaylistSongsScreen({
    required this.playlistTitle,
    required this.playlistId,
    required this.bridgeUrl,
    this.thumbnailUrl,
  });

  @override
  State<_PlaylistSongsScreen> createState() => _PlaylistSongsScreenState();
}

class _PlaylistSongsScreenState extends State<_PlaylistSongsScreen> {
  final MuslyBackendService _backend = MuslyBackendService();
  List<Song> _songs = [];
  bool _isLoading = true;
  String? _error;

  String _getEffectiveBridgeUrl() {
    if (widget.bridgeUrl.isNotEmpty) return widget.bridgeUrl;
    try {
      final config = Provider.of<SubsonicService>(context, listen: false).config;
      return config?.bridgeUrl ?? '';
    } catch (_) {
      return '';
    }
  }

  @override
  void initState() {
    super.initState();
    _loadSongs();
  }

  Future<void> _loadSongs() async {
    final bridgeUrl = _getEffectiveBridgeUrl();
    if (bridgeUrl.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'Bridge server unavailable';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      _songs = await _backend.getPlaylistSongs(
        bridgeUrl,
        widget.playlistId,
      );
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _playAll() {
    if (_songs.isEmpty) return;
    final playerProvider = Provider.of<PlayerProvider>(context, listen: false);
    playerProvider.playSong(_songs.first, playlist: _songs, startIndex: 0);
  }

  void _playShuffle() {
    if (_songs.isEmpty) return;
    final playerProvider = Provider.of<PlayerProvider>(context, listen: false);
    final shuffled = List<Song>.from(_songs)..shuffle();
    playerProvider.playSong(shuffled.first, playlist: shuffled, startIndex: 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: widget.thumbnailUrl != null ? 200 : null,
            title: widget.thumbnailUrl == null ? Text(widget.playlistTitle) : null,
            flexibleSpace: widget.thumbnailUrl != null
                ? FlexibleSpaceBar(
                    title: Text(
                      widget.playlistTitle,
                      style: theme.appBarTheme.titleTextStyle?.copyWith(fontSize: 16),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    titlePadding: const EdgeInsets.only(left: 52, bottom: 16, right: 16),
                    background: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedNetworkImage(
                          imageUrl: widget.thumbnailUrl!,
                          fit: BoxFit.cover,
                        ),
                        Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                (isDark ? Colors.black : Colors.white)
                                    .withValues(alpha: 0.9),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  )
                : null,
          ),
          if (_isLoading)
            SliverToBoxAdapter(
              child: Column(
                children: List.generate(10, (_) => const SongTileShimmer()),
              ),
            )
          else if (_error != null)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline,
                        size: 64, color: AppTheme.lightSecondaryText),
                    const SizedBox(height: 16),
                    Text('Error loading songs',
                        style: theme.textTheme.headlineSmall),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _loadSongs,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
            )
          else if (_songs.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Text('No songs found',
                    style: theme.textTheme.headlineSmall),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  if (index == 0) {
                    // Play controls row
                    return Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        children: [
                          Text(
                            '${_songs.length} songs',
                            style: TextStyle(
                              color: isDark ? Colors.white60 : Colors.black54,
                              fontSize: 14,
                            ),
                          ),
                          const Spacer(),
                          IconButton(
                            onPressed: _playShuffle,
                            icon: Icon(
                              Icons.shuffle_rounded,
                              color:
                                  isDark ? Colors.white70 : Colors.black54,
                              size: 28,
                            ),
                            tooltip: 'Shuffle play',
                          ),
                          const SizedBox(width: 8),
                          Consumer<PlayerProvider>(
                            builder: (context, playerProvider, _) {
                              final isCurrentPlaylist =
                                  playerProvider.queue.isNotEmpty &&
                                      playerProvider.queue.any(
                                        (song) =>
                                            _songs.any((s) => s.id == song.id),
                                      );
                              final isPlaying =
                                  isCurrentPlaylist && playerProvider.isPlaying;

                              return GestureDetector(
                                onTap: () {
                                  if (isCurrentPlaylist &&
                                      playerProvider.currentSong != null) {
                                    if (playerProvider.isPlaying) {
                                      playerProvider.pause();
                                    } else {
                                      playerProvider.play();
                                    }
                                  } else {
                                    _playAll();
                                  }
                                },
                                child: Container(
                                  width: 48,
                                  height: 48,
                                  decoration: BoxDecoration(
                                    color: AppTheme.appleMusicRed,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: AppTheme.appleMusicRed
                                            .withValues(alpha: 0.4),
                                        blurRadius: 12,
                                        offset: const Offset(0, 4),
                                      ),
                                    ],
                                  ),
                                  child: Icon(
                                    isPlaying
                                        ? Icons.pause_rounded
                                        : Icons.play_arrow_rounded,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  }

                  final songIndex = index - 1;
                  if (songIndex >= _songs.length) {
                    return const SizedBox(height: 120);
                  }

                  return SongTile(
                    song: _songs[songIndex],
                    playlist: _songs,
                    index: songIndex,
                    showArtist: true,
                    showAlbum: true,
                  );
                },
                childCount: _songs.length + 2,
              ),
            ),
        ],
      ),
    );
  }
}
