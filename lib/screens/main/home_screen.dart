import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:musly/models/models.dart';
import 'package:musly/providers/library_provider.dart';
import 'package:musly/providers/player_provider.dart';
import 'package:musly/providers/auth_provider.dart';
import 'package:musly/services/subsonic_service.dart';
import 'package:musly/services/recommendation_service.dart';
import 'package:musly/services/offline_service.dart';
import 'package:musly/theme/app_theme.dart';
import 'package:musly/utils/navigation_helper.dart';
import 'package:musly/widgets/widgets.dart';
import 'package:musly/screens/detail/album_screen.dart';
import 'package:musly/screens/detail/playlist_screen.dart';
import 'package:musly/screens/detail/artist_screen.dart';
import 'package:musly/screens/media/song_collection_screen.dart';
import 'package:musly/screens/media/favorites_screen.dart';
import 'package:musly/screens/settings/settings_screen.dart';
import 'package:musly/screens/wrapped/wrapped_screen.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:musly/providers/recommendations_provider.dart';
import 'package:musly/screens/media/recommendations_screen.dart';
import 'package:musly/l10n/app_localizations.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  Map<String, List<Song>> _cachedMixes = const {};
  List<Song> _cachedPersonalized = const [];
  List<Song> _cachedListenAgain = const [];
  List<Song> _cachedTopHits = const [];
  String _lastRandomKey = '';
  String _selectedCategory = 'All';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadRecommendations();
    });
  }

  String _resolveBridgeUrl() {
    return Provider.of<SubsonicService>(context, listen: false).bridgeUrl ?? '';
  }

  Future<void> _loadRecommendations() async {
    try {
      final bridgeUrl = _resolveBridgeUrl();
      if (bridgeUrl.isNotEmpty) {
        final recProvider =
            Provider.of<RecommendationsProvider>(context, listen: false);
        if (!recProvider.initialized) {
          recProvider.loadMoodCategories(bridgeUrl);
        }
        if (!recProvider.featuredInitialized) {
          recProvider.loadFeaturedPlaylists(bridgeUrl);
        }
      }
    } catch (e) {
      debugPrint('Failed to load recommendations on home screen: $e');
    }
  }

  String _getGreeting() {
    final hour = DateTime.now().hour;
    if (hour < 12) {
      return AppLocalizations.of(context)?.goodMorning ?? 'Good morning';
    }
    if (hour < 17) {
      return AppLocalizations.of(context)?.goodAfternoon ?? 'Good afternoon';
    }
    return AppLocalizations.of(context)?.goodEvening ?? 'Good evening';
  }

  String _computeRandomKey(List<Song> songs, RecommendationService rec) {
    if (songs.isEmpty) return '';
    final lastPlayed =
        rec.recentlyPlayed.isNotEmpty ? rec.recentlyPlayed.first : '';
    return '${songs.length}_${songs.first.id}_${songs.last.id}_${rec.profiles.length}_${rec.recentlyPlayed.length}_$lastPlayed';
  }

  bool get _isDesktop =>
      Platform.isMacOS || Platform.isWindows || Platform.isLinux;

  void _openAlbum(BuildContext context, String albumId) {
    NavigationHelper.push(
      context,
      AlbumScreen(albumId: albumId),
    );
  }

  void _openPlaylist(BuildContext context, Playlist playlist) {
    NavigationHelper.push(
      context,
      PlaylistScreen(playlistId: playlist.id, playlistName: playlist.name),
    );
  }

  void _openArtist(BuildContext context, String artistId) {
    NavigationHelper.push(
      context,
      ArtistScreen(artistId: artistId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isDesktop = _isDesktop;
    final hPad = isDesktop ? 32.0 : 16.0;
    final authProvider = Provider.of<AuthProvider>(context);
    final subsonicService = Provider.of<SubsonicService>(context);

    return Scaffold(
      backgroundColor:
          isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      body: RefreshIndicator(
        color: Theme.of(context).colorScheme.primary,
        onRefresh: () async {
          final libraryProvider =
              Provider.of<LibraryProvider>(context, listen: false);
          await libraryProvider.refresh();
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics()),
          slivers: [
            SliverAppBar(
              automaticallyImplyLeading: false,
              pinned: true,
              floating: true,
              expandedHeight: 110,
              backgroundColor:
                  isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
              elevation: 0,
              flexibleSpace: FlexibleSpaceBar(
                titlePadding: EdgeInsets.only(left: hPad, bottom: 48),
                title: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      _getGreeting(),
                      style: TextStyle(
                        fontSize: isDesktop ? 24 : 20,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : Colors.black87,
                        letterSpacing: -0.5,
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                IconButton(
                  icon: Icon(
                    CupertinoIcons.clock,
                    color: isDark ? Colors.white : Colors.black87,
                    size: 22,
                  ),
                  tooltip: AppLocalizations.of(context)!.history,
                  onPressed: () =>
                      NavigationHelper.push(context, const HistoryScreen()),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: Center(
                    child: UserProfileAvatar(
                      size: 42,
                      onTap: () =>
                          NavigationHelper.push(context, const SettingsScreen()),
                    ),
                  ),
                ),
                if (isDesktop) const SizedBox(width: 12),
              ],
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(48),
                child: Container(
                  height: 48,
                  padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 6),
                  alignment: Alignment.centerLeft,
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    physics: const BouncingScrollPhysics(),
                    child: Row(
                      children: [
                        _buildCategoryChip('All', 'All', isDark),
                        const SizedBox(width: 8),
                        _buildCategoryChip('Music', 'Music', isDark),
                        const SizedBox(width: 8),
                        _buildCategoryChip(
                            'MadeForYou', 'Made For You', isDark),
                        const SizedBox(width: 8),
                        _buildCategoryChip('Playlists', 'Playlists', isDark),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SliverToBoxAdapter(
              child: Consumer2<LibraryProvider, RecommendationService>(
                builder: (context, libraryProvider, recommendationService, _) {
                  if (libraryProvider.isLoading &&
                      !libraryProvider.isInitialized) {
                    return _buildLoadingState(isDesktop, hPad);
                  }

                  final allSongs = libraryProvider.cachedAllSongs.isNotEmpty
                      ? libraryProvider.cachedAllSongs
                      : libraryProvider.randomSongs;
                  final key =
                      _computeRandomKey(allSongs, recommendationService);

                  if (recommendationService.enabled && key.isNotEmpty) {
                    if (key != _lastRandomKey) {
                      _cachedMixes =
                          recommendationService.generateMixes(allSongs);
                      _cachedPersonalized = recommendationService
                          .getPersonalizedFeed(allSongs, limit: 12);
                      _cachedListenAgain = recommendationService
                          .getListenAgain(allSongs, limit: 10);
                      _cachedTopHits =
                          recommendationService.getTopHits(allSongs, limit: 10);
                      _lastRandomKey = key;
                    }
                  } else {
                    _cachedMixes = const {};
                    _cachedPersonalized = const [];
                    _cachedListenAgain = const [];
                    _cachedTopHits = const [];
                    _lastRandomKey = '';
                  }

                  var mixes = _cachedMixes;
                  var personalizedFeed = _cachedPersonalized;
                  var listenAgain = _cachedListenAgain;
                  var topHits = _cachedTopHits;
                  var recentAlbums = libraryProvider.recentAlbums;
                  var playlists = libraryProvider.playlists;
                  var artists = libraryProvider.artists;

                  if (artists.isEmpty && recommendationService.enabled) {
                    final topNames =
                        recommendationService.getRecommendedArtists(limit: 10);
                    if (topNames.isNotEmpty) {
                      artists = topNames
                          .map((name) => Artist(id: 'yt-$name', name: name))
                          .toList();
                    }
                  }

                  final isOffline = authProvider.state == AuthState.offlineMode;
                  final offlineService = OfflineService();

                  if (isOffline) {
                    final downloadedIds =
                        offlineService.getDownloadedSongIds().toSet();
                    final downloadedPlaylistIds =
                        offlineService.downloadedPlaylistIds.value.toSet();
                    final allSongs = libraryProvider.cachedAllSongs;
                    final Set<String> downloadedAlbumIds = {};
                    for (final song in allSongs) {
                      if (downloadedIds.contains(song.id) &&
                          song.albumId != null) {
                        downloadedAlbumIds.add(song.albumId!);
                      }
                    }

                    recentAlbums = recentAlbums
                        .where((a) => downloadedAlbumIds.contains(a.id))
                        .toList();
                    playlists = playlists
                        .where((p) => downloadedPlaylistIds.contains(p.id))
                        .toList();

                    final Map<String, List<Song>> offlineMixes = {};
                    for (final entry in mixes.entries) {
                      final filtered = entry.value
                          .where((s) => downloadedIds.contains(s.id))
                          .toList();
                      if (filtered.isNotEmpty) {
                        offlineMixes[entry.key] = filtered;
                      }
                    }
                    mixes = offlineMixes;

                    personalizedFeed = personalizedFeed
                        .where((s) => downloadedIds.contains(s.id))
                        .toList();
                    listenAgain = listenAgain
                        .where((s) => downloadedIds.contains(s.id))
                        .toList();
                    topHits = topHits
                        .where((s) => downloadedIds.contains(s.id))
                        .toList();
                  }

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (!isDesktop && WrappedService.isWrappedSeason()) ...[
                          _buildWrappedBanner(context, hPad, isDesktop),
                          const SizedBox(height: 12),
                        ],
                        if (_selectedCategory == 'All' ||
                            _selectedCategory == 'Music') ...[
                          const SizedBox(height: 8),
                          _buildSpotifyTopGrid(
                            context,
                            recentAlbums: recentAlbums,
                            playlists: playlists,
                            mixes: mixes,
                            subsonicService: subsonicService,
                            isDesktop: isDesktop,
                            hPad: hPad,
                          ),
                          const SizedBox(height: 24),
                        ],
                        if ((_selectedCategory == 'All' ||
                                _selectedCategory == 'Music') &&
                            recentAlbums.isNotEmpty) ...[
                          HorizontalScrollSection(
                            title: 'Jump back in',
                            padding: EdgeInsets.symmetric(horizontal: hPad),
                            cardSize: isDesktop ? 180 : 155,
                            children: recentAlbums.take(12).map((album) {
                              return MediaCard(
                                title: album.name,
                                subtitle: album.artist,
                                coverArt: album.coverArt,
                                size: isDesktop ? 180 : 155,
                                onTap: () => _openAlbum(context, album.id),
                                onPlayPressed: () =>
                                    _playAlbum(context, album.id),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 28),
                        ],
                        // YT Music Featured Playlists section
                        Consumer<RecommendationsProvider>(
                          builder: (context, recProvider, _) {
                            if (recProvider.loadingFeatured && !recProvider.hasFeaturedData) {
                              return Padding(
                                padding: EdgeInsets.symmetric(horizontal: hPad),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        const YouTubeMusicLogo(size: 20),
                                        const SizedBox(width: 8),
                                        Text(
                                          AppLocalizations.of(context)?.featuredPlaylists ?? 'Featured Playlists',
                                          style: TextStyle(
                                            fontSize: isDesktop ? 20 : 18,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 12),
                                    SizedBox(
                                      height: (isDesktop ? 160.0 : 130.0) + 56.0,
                                      child: ListView.builder(
                                        scrollDirection: Axis.horizontal,
                                        itemCount: 6,
                                        itemBuilder: (_, __) => Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 5),
                                          child: Container(
                                            width: isDesktop ? 160.0 : 130.0,
                                            height: isDesktop ? 160.0 : 130.0,
                                            decoration: BoxDecoration(
                                              color: isDark ? const Color(0xFF282828) : Colors.grey[200],
                                              borderRadius: BorderRadius.circular(10),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 24),
                                  ],
                                ),
                              );
                            }

                            if (!recProvider.hasFeaturedData) {
                              return const SizedBox.shrink();
                            }

                            final effectiveBridgeUrl = _resolveBridgeUrl();
                            final cardSize = isDesktop ? 160.0 : 130.0;
                            final totalHeight = cardSize + 56.0;

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: hPad),
                                  child: Row(
                                    children: [
                                      const YouTubeMusicLogo(size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        AppLocalizations.of(context)?.featuredPlaylists ?? 'Featured Playlists',
                                        style: TextStyle(
                                          fontSize: isDesktop ? 20 : 18,
                                          fontWeight: FontWeight.bold,
                                          color: isDark ? Colors.white : Colors.black87,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: totalHeight,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    padding: EdgeInsets.symmetric(horizontal: hPad - 5),
                                    itemCount: recProvider.featuredPlaylists.length,
                                    itemBuilder: (context, index) {
                                      final playlist = recProvider.featuredPlaylists[index];
                                      return _FeaturedPlaylistSquareCard(
                                        playlist: playlist,
                                        size: cardSize,
                                        onTap: () => NavigationHelper.push(
                                          context,
                                          PlaylistSongsScreen(
                                            playlistTitle: playlist.title,
                                            playlistId: playlist.playlistId,
                                            bridgeUrl: effectiveBridgeUrl,
                                            thumbnailUrl: playlist.thumbnailUrl,
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 24),
                              ],
                            );
                          },
                        ),

                        // YT Music Moods & Genres recommendations section
                        Consumer<RecommendationsProvider>(
                          builder: (context, recProvider, _) {
                            if (recProvider.loading || !recProvider.hasData) {
                              return const SizedBox.shrink();
                            }
                            final previewCats = <MapEntry<String, dynamic>>[];
                            for (final section in recProvider.sections) {
                              for (final cat in section.categories.take(4)) {
                                previewCats.add(MapEntry(section.name, cat));
                              }
                              if (previewCats.length >= 8) break;
                            }
                            if (previewCats.isEmpty) return const SizedBox.shrink();
                            final effectiveBridgeUrl = _resolveBridgeUrl();

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: hPad),
                                  child: GestureDetector(
                                    onTap: () => NavigationHelper.push(
                                      context,
                                      const RecommendationsScreen(),
                                    ),
                                    child: Row(
                                      children: [
                                        const YouTubeMusicLogo(size: 20),
                                        const SizedBox(width: 8),
                                        Text(
                                          AppLocalizations.of(context)?.recommendations ?? 'Recommendations',
                                          style: TextStyle(
                                            fontSize: isDesktop ? 20 : 18,
                                            fontWeight: FontWeight.bold,
                                            color: isDark ? Colors.white : Colors.black87,
                                          ),
                                        ),
                                        const Spacer(),
                                        Icon(
                                          CupertinoIcons.chevron_forward,
                                          size: 16,
                                          color: isDark ? Colors.white54 : Colors.black45,
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 12),
                                SizedBox(
                                  height: 80,
                                  child: ListView.builder(
                                    scrollDirection: Axis.horizontal,
                                    padding: EdgeInsets.symmetric(horizontal: hPad - 4),
                                    itemCount: previewCats.length,
                                    itemBuilder: (context, index) {
                                      final cat = previewCats[index].value;
                                      final colors = [
                                        [const Color(0xFF8B5CF6), const Color(0xFFEC4899)],
                                        [const Color(0xFF10B981), const Color(0xFF06B6D4)],
                                        [const Color(0xFFF59E0B), const Color(0xFFEF4444)],
                                        [const Color(0xFF3B82F6), const Color(0xFF6366F1)],
                                      ];
                                      final pair = colors[index % colors.length];
                                      return Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 4),
                                        child: SizedBox(
                                          width: 120,
                                          child: Material(
                                            color: Colors.transparent,
                                            child: InkWell(
                                              borderRadius: BorderRadius.circular(10),
                                              onTap: () => NavigationHelper.push(
                                                context,
                                                MoodPlaylistsScreen(
                                                  categoryTitle: cat.title,
                                                  categoryParams: cat.params,
                                                  bridgeUrl: effectiveBridgeUrl,
                                                ),
                                              ),
                                              child: Container(
                                                decoration: BoxDecoration(
                                                  gradient: LinearGradient(
                                                    colors: pair,
                                                    begin: Alignment.topLeft,
                                                    end: Alignment.bottomRight,
                                                  ),
                                                  borderRadius: BorderRadius.circular(10),
                                                ),
                                                padding: const EdgeInsets.all(10),
                                                child: Text(
                                                  cat.title,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 13,
                                                  ),
                                                  maxLines: 2,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                                const SizedBox(height: 24),
                              ],
                            );
                          },
                        ),
                        if ((_selectedCategory == 'All' ||
                                _selectedCategory == 'MadeForYou') &&
                            recommendationService.enabled &&
                            personalizedFeed.isNotEmpty) ...[
                          _buildMixSection(
                            context: context,
                            title: 'Made For You',
                            icon: Icons.auto_awesome,
                            songs: personalizedFeed,
                            isDesktop: isDesktop,
                            hPad: hPad,
                          ),
                          const SizedBox(height: 28),
                        ],
                        if ((_selectedCategory == 'All' ||
                                _selectedCategory == 'Music') &&
                            listenAgain.isNotEmpty) ...[
                          _buildMixSection(
                            context: context,
                            title: 'Listen Again',
                            icon: Icons.history_rounded,
                            songs: listenAgain,
                            isDesktop: isDesktop,
                            hPad: hPad,
                          ),
                          const SizedBox(height: 28),
                        ],
                        if ((_selectedCategory == 'All' ||
                                _selectedCategory == 'MadeForYou') &&
                            topHits.isNotEmpty) ...[
                          _buildMixSection(
                            context: context,
                            title: 'Your Top Hits',
                            icon: Icons.favorite_rounded,
                            songs: topHits,
                            isDesktop: isDesktop,
                            hPad: hPad,
                          ),
                          const SizedBox(height: 28),
                        ],
                        if ((_selectedCategory == 'All' ||
                                _selectedCategory == 'Playlists') &&
                            playlists.isNotEmpty) ...[
                          HorizontalScrollSection(
                            title: 'Your Playlists',
                            padding: EdgeInsets.symmetric(horizontal: hPad),
                            cardSize: isDesktop ? 180 : 155,
                            children: playlists.take(12).map((playlist) {
                              return MediaCard(
                                title: playlist.name,
                                subtitle: 'Playlist • Musly',
                                coverArt: playlist.coverArt,
                                size: isDesktop ? 180 : 155,
                                onTap: () => _openPlaylist(context, playlist),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 28),
                        ],
                        if (_selectedCategory == 'All' ||
                            _selectedCategory == 'MadeForYou') ...[
                          for (final entry in mixes.entries.take(4))
                            Padding(
                              padding: const EdgeInsets.only(bottom: 28),
                              child: _buildMixSection(
                                context: context,
                                title: entry.key,
                                icon: Icons.graphic_eq_rounded,
                                songs: entry.value,
                                isDesktop: isDesktop,
                                hPad: hPad,
                              ),
                            ),
                        ],
                        if ((_selectedCategory == 'All' ||
                                _selectedCategory == 'Music') &&
                            artists.isNotEmpty) ...[
                          HorizontalScrollSection(
                            title: 'Artists You Love',
                            padding: EdgeInsets.symmetric(horizontal: hPad),
                            cardSize: isDesktop ? 160 : 140,
                            children: artists.take(10).map((artist) {
                              final coverArt = artist.coverArt ??
                                  artist.artistImageUrl ??
                                  (artist.id.isNotEmpty
                                      ? 'ar-${artist.id}'
                                      : null);
                              return MediaCard(
                                title: artist.name,
                                subtitle: 'Artist',
                                coverArt: coverArt,
                                isRound: true,
                                size: isDesktop ? 160 : 140,
                                onTap: () => _openArtist(context, artist.id),
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 20),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCategoryChip(String key, String label, bool isDark) {
    final isSelected = _selectedCategory == key;
    final primary = Theme.of(context).colorScheme.primary;
    final onPrimary =
        ThemeData.estimateBrightnessForColor(primary) == Brightness.dark
            ? Colors.white
            : Colors.black;

    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = key),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? primary
              : (isDark ? const Color(0xFF2A2A2A) : const Color(0xFFE5E7EB)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: isSelected
                ? onPrimary
                : (isDark ? Colors.white : Colors.black87),
          ),
        ),
      ),
    );
  }

  Widget _buildSpotifyTopGrid(
    BuildContext context, {
    required List<Album> recentAlbums,
    required List<Playlist> playlists,
    required Map<String, List<Song>> mixes,
    required SubsonicService subsonicService,
    required bool isDesktop,
    required double hPad,
  }) {
    final cols = isDesktop ? 4 : 2;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final spacing = 8.0;
          final totalSpacing = spacing * (cols - 1);
          final cardWidth = (constraints.maxWidth - totalSpacing) / cols;

          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              SizedBox(
                width: cardWidth,
                child: QuickAccessTile(
                  title: 'Liked Songs',
                  customArtwork: Container(
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF450AF5), Color(0xFF8E8EE5)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                    child: const Center(
                      child: Icon(CupertinoIcons.heart_fill,
                          color: Colors.white, size: 22),
                    ),
                  ),
                  onTap: () =>
                      NavigationHelper.push(context, const FavoritesScreen()),
                ),
              ),
              ...playlists.take(2).map((playlist) {
                return SizedBox(
                  width: cardWidth,
                  child: QuickAccessTile(
                    title: playlist.name,
                    imageUrl: playlist.coverArt,
                    onTap: () => _openPlaylist(context, playlist),
                  ),
                );
              }),
              if (recentAlbums.isNotEmpty)
                ...recentAlbums.take(cols == 4 ? 5 : 3).map((album) {
                  return SizedBox(
                    width: cardWidth,
                    child: QuickAccessTile(
                      title: album.name,
                      imageUrl: album.coverArt,
                      onTap: () => _openAlbum(context, album.id),
                      onPlayPressed: () => _playAlbum(context, album.id),
                    ),
                  );
                })
              else
                ...mixes.entries.take(cols == 4 ? 5 : 3).map((entry) {
                  final songs = entry.value;
                  final firstCover =
                      songs.isNotEmpty ? songs.first.coverArt : null;
                  return SizedBox(
                    width: cardWidth,
                    child: QuickAccessTile(
                      title: entry.key,
                      imageUrl: firstCover,
                      onTap: () {
                        if (songs.isNotEmpty) {
                          _playSong(context, songs.first, songs);
                        }
                      },
                      onPlayPressed: () {
                        if (songs.isNotEmpty) {
                          _playSong(context, songs.first, songs);
                        }
                      },
                    ),
                  );
                }),
            ],
          );
        },
      ),
    );
  }

  Widget _buildMixSection({
    required BuildContext context,
    required String title,
    required IconData icon,
    required List<Song> songs,
    required bool isDesktop,
    required double hPad,
  }) {
    final cardSize = isDesktop ? 180.0 : 155.0;

    return HorizontalScrollSection(
      title: title,
      padding: EdgeInsets.symmetric(horizontal: hPad),
      cardSize: cardSize,
      children: songs.take(12).map((song) {
        return MediaCard(
          title: song.title,
          subtitle: song.artist,
          coverArt: song.coverArt,
          size: cardSize,
          onTap: () => _playSong(context, song, songs),
          onPlayPressed: () => _playSong(context, song, songs),
        );
      }).toList(),
    );
  }

  Future<void> _playSong(
      BuildContext context, Song song, List<Song> queue) async {
    final playerProvider = Provider.of<PlayerProvider>(context, listen: false);
    final idx = queue.indexOf(song);
    await playerProvider.playSong(song,
        playlist: queue, startIndex: idx >= 0 ? idx : 0);
  }

  Future<void> _playAlbum(BuildContext context, String albumId) async {
    try {
      final subsonicService =
          Provider.of<SubsonicService>(context, listen: false);
      final playerProvider =
          Provider.of<PlayerProvider>(context, listen: false);
      final songs = await subsonicService.getAlbumSongs(albumId);
      if (songs.isNotEmpty) {
        await playerProvider.playSong(songs.first,
            playlist: songs, startIndex: 0);
      }
    } catch (e) {
      debugPrint('Error playing album: $e');
    }
  }

  Widget _buildLoadingState(bool isDesktop, double hPad) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  height: 56,
                  decoration: BoxDecoration(
                    color: Colors.white10,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          Container(
            width: 140,
            height: 20,
            decoration: BoxDecoration(
              color: Colors.white10,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 160,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: 4,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (_, __) => Container(
                width: 140,
                decoration: BoxDecoration(
                  color: Colors.white10,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWrappedBanner(
      BuildContext context, double hPad, bool isDesktop) {
    final year = WrappedService.getWrappedYear();
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            NavigationHelper.push(context, const WrappedScreen());
          },
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFA243C), Color(0xFF8B5CF6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFA243C).withValues(alpha: 0.35),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(CupertinoIcons.sparkles,
                      color: Colors.white, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '#MuslyPlayback $year',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.1,
                        ),
                      ),
                      Text(
                        AppLocalizations.of(context)?.yourYearInReviewIsReady ??
                            'Your Year in Review is ready!',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(CupertinoIcons.chevron_forward,
                    color: Colors.white, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeaturedPlaylistSquareCard extends StatelessWidget {
  final MoodPlaylist playlist;
  final VoidCallback onTap;
  final double size;

  const _FeaturedPlaylistSquareCard({
    required this.playlist,
    required this.onTap,
    this.size = 140,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 5),
      child: SizedBox(
        width: size,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.25),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: playlist.thumbnailUrl != null &&
                          playlist.thumbnailUrl!.isNotEmpty
                      ? CachedNetworkImage(
                          imageUrl: playlist.thumbnailUrl!,
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => Container(
                            color: isDark ? const Color(0xFF282828) : Colors.grey[200],
                            child: const Icon(CupertinoIcons.music_albums, size: 40),
                          ),
                        )
                      : Container(
                          color: isDark ? const Color(0xFF282828) : Colors.grey[200],
                          child: const Icon(CupertinoIcons.music_albums, size: 40),
                        ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                playlist.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
              if (playlist.subtitle != null && playlist.subtitle!.isNotEmpty)
                Text(
                  playlist.subtitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
