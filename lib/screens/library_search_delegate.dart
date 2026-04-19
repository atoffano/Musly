import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../theme/app_theme.dart';
import '../utils/navigation_helper.dart';
import 'playlist_screen.dart';

class LibrarySearchDelegate extends SearchDelegate<String> {
  final LibraryProvider libraryProvider;
  final bool isDark;

  LibrarySearchDelegate({required this.libraryProvider, required this.isDark})
    : super(
        searchFieldLabel: 'Search in Library...',
        searchFieldStyle: TextStyle(
          color: isDark ? Colors.white : Colors.black,
        ),
      );

  @override
  ThemeData appBarTheme(BuildContext context) {
    final theme = Theme.of(context);
    return theme.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: isDark ? AppTheme.darkBackground : Colors.white,
        elevation: 0.5,
        iconTheme: IconThemeData(color: isDark ? Colors.white : Colors.black),
      ),
      inputDecorationTheme: InputDecorationTheme(
        hintStyle: TextStyle(color: isDark ? Colors.white54 : Colors.black45),
      ),
    );
  }

  @override
  List<Widget> buildActions(BuildContext context) {
    return [
      if (query.isNotEmpty)
        IconButton(icon: const Icon(Icons.clear), onPressed: () => query = ''),
    ];
  }

  @override
  Widget buildLeading(BuildContext context) {
    return IconButton(
      icon: const Icon(Icons.arrow_back),
      onPressed: () => close(context, ''),
    );
  }

  @override
  Widget buildResults(BuildContext context) {
    return _buildSearchResults(context);
  }

  @override
  Widget buildSuggestions(BuildContext context) {
    if (query.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.search,
              size: 64,
              color: isDark ? Colors.white38 : Colors.black26,
            ),
            const SizedBox(height: 16),
            Text(
              'Search your library',
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black45,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }
    return _buildSearchResults(context);
  }

  Widget _buildSearchResults(BuildContext context) {
    final lowerQuery = query.toLowerCase();

    final matchingPlaylists = libraryProvider.playlists
        .where((p) => p.name.toLowerCase().contains(lowerQuery))
        .toList();

    final matchingSongs = libraryProvider.cachedAllSongs
        .where(
          (s) =>
              s.title.toLowerCase().contains(lowerQuery) ||
              (s.artist?.toLowerCase().contains(lowerQuery) ?? false) ||
              (s.album?.toLowerCase().contains(lowerQuery) ?? false),
        )
        .take(50)
        .toList();

    if (matchingPlaylists.isEmpty && matchingSongs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              CupertinoIcons.search,
              size: 64,
              color: isDark ? Colors.white38 : Colors.black26,
            ),
            const SizedBox(height: 16),
            Text(
              'No results found',
              style: TextStyle(
                color: isDark ? Colors.white54 : Colors.black45,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      children: [
        if (matchingPlaylists.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Playlists',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
          ...matchingPlaylists.map(
            (playlist) => ListTile(
              leading: Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: AppTheme.appleMusicRed.withValues(alpha: 0.2),
                ),
                child: const Icon(
                  CupertinoIcons.music_note_list,
                  color: AppTheme.appleMusicRed,
                ),
              ),
              title: Text(playlist.name),
              subtitle: Text('${playlist.songCount} songs'),
              onTap: () {
                close(context, '');
                NavigationHelper.push(
                  context,
                  PlaylistScreen(
                    playlistId: playlist.id,
                    playlistName: playlist.name,
                  ),
                );
              },
            ),
          ),
        ],
        if (matchingSongs.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Songs',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
          ),
          ...matchingSongs.asMap().entries.map(
            (entry) => _buildSongResultTile(
              context,
              entry.value,
              matchingSongs,
              entry.key,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSongResultTile(
    BuildContext context,
    Song song,
    List<Song> playlist,
    int index,
  ) {
    final secondary = isDark ? Colors.white70 : Colors.black54;
    return ListTile(
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
        ),
        child: const Icon(CupertinoIcons.music_note, size: 20),
      ),
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [song.artist, song.album].whereType<String>().where((v) => v.isNotEmpty).join(' • '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: secondary),
      ),
      onTap: () {
        final player = Provider.of<PlayerProvider>(context, listen: false);
        close(context, '');
        player.playSong(song, playlist: playlist, startIndex: index);
      },
    );
  }
}
