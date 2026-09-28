import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../providers/providers.dart';
import '../services/subsonic_service.dart';
import '../theme/app_theme.dart';
import '../utils/navigation_helper.dart';
import 'album_screen.dart';
import 'package:musly/screens/playlist_screen.dart';
import 'favorites_screen.dart';
import 'all_albums_screen.dart';
import 'all_songs_screen.dart';
import 'library_search_delegate.dart';
import 'artist_screen.dart';
import 'radio_screen.dart';
import '../l10n/app_localizations.dart';
import '../widgets/album_artwork.dart' show isLocalFilePath;
import '../widgets/user_profile_avatar.dart';
import '../widgets/playlist_options_sheet.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  String _selectedFilter = 'All';
  final List<String> _filters = ['All', 'Faves', 'Albums', 'Artists', 'Songs'];
  bool _isPlaylistActionBusy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            floating: true,
            expandedHeight: 60,
            backgroundColor: isDark ? AppTheme.darkBackground : Colors.white,
            title: Text(
              AppLocalizations.of(context)!.yourLibrary,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black,
              ),
            ),
            actions: [
              
              IconButton(
                icon: Icon(
                  CupertinoIcons.refresh,
                  color: isDark ? Colors.white : Colors.black,
                ),
                onPressed: () {
                  final libraryProvider = Provider.of<LibraryProvider>(
                    context,
                    listen: false,
                  );
                  libraryProvider.refresh();
                },
              ),
              IconButton(
                icon: Icon(
                  CupertinoIcons.search,
                  color: isDark ? Colors.white : Colors.black,
                ),
                onPressed: () => _showLibrarySearch(context),
              ),
              IconButton(
                icon: Icon(
                  CupertinoIcons.plus,
                  color: isDark ? Colors.white : Colors.black,
                ),
                onPressed: () => _showCreatePlaylistDialog(context),
              ),
              const Padding(
                padding: EdgeInsets.only(right: 8.0),
                child: UserProfileAvatar(size: 42),
              ),
            ],
          ),

          SliverToBoxAdapter(
            child: Builder(
              builder: (context) {
                final l10n = AppLocalizations.of(context)!;
                final filterLabels = {
                  'All': l10n.filterAll,
                  'Faves': 'Faves',
                  'Albums': l10n.filterAlbums,
                  'Artists': l10n.filterArtists,
                  'Songs': l10n.songs,
                };
                return SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: _filters.map((filter) {
                      final isSelected = _selectedFilter == filter;
                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(filterLabels[filter]!),
                          selected: isSelected,
                          onSelected: (selected) {
                            setState(() {
                              _selectedFilter = selected ? filter : 'All';
                            });
                          },
                          backgroundColor: isDark
                              ? const Color(0xFF282828)
                              : Colors.grey[200],
                          selectedColor: isDark ? Colors.white : Colors.black,
                          labelStyle: TextStyle(
                            color: isSelected
                                ? (isDark ? Colors.black : Colors.white)
                                : (isDark ? Colors.white : Colors.black),
                            fontWeight: FontWeight.w500,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          side: BorderSide.none,
                          showCheckmark: false,
                        ),
                      );
                    }).toList(),
                  ),
                );
              },
            ),
          ),

          SliverToBoxAdapter(
            child: Column(
              children: [
                if (_selectedFilter == 'Songs') ...[
                  _SpotifyLibraryTile(
                    icon: CupertinoIcons.music_note_list,
                    iconColor: const Color(0xFF10B981),
                    title: AppLocalizations.of(context)!.allSongs,
                    subtitle: AppLocalizations.of(context)!.songs,
                    isGradient: false,
                    onTap: () => _navigate(context, const AllSongsScreen()),
                  ),
                ],
                if (_selectedFilter == 'All' || _selectedFilter == 'Faves') ...[
                  if (_selectedFilter == 'All') ...[  
                    _SpotifyLibraryTile(
                      icon: CupertinoIcons.heart_fill,
                      iconColor: const Color(0xFF8B5CF6),
                      title: AppLocalizations.of(context)!.likedSongs,
                      subtitle: AppLocalizations.of(context)!.playlist,
                      isGradient: true,
                      onTap: () => _navigate(context, const FavoritesScreen()),
                    ),
                    _SpotifyLibraryTile(
                      icon: CupertinoIcons.music_albums,
                      iconColor: const Color(0xFFEC4899),
                      title: AppLocalizations.of(context)!.allAlbums,
                      subtitle: AppLocalizations.of(context)!.filterAlbums,
                      isGradient: false,
                      onTap: () => _navigate(context, const AllAlbumsScreen()),
                    ),
                    _SpotifyLibraryTile(
                      icon: CupertinoIcons.music_note_list,
                      iconColor: const Color(0xFF10B981),
                      title: AppLocalizations.of(context)!.allSongs,
                      subtitle: AppLocalizations.of(context)!.songs,
                      isGradient: false,
                      onTap: () => _navigate(context, const AllSongsScreen()),
                    ),
                    _SpotifyLibraryTile(
                      icon: CupertinoIcons.radiowaves_right,
                      iconColor: const Color(0xFF3B82F6),
                      title: AppLocalizations.of(context)!.radioStations,
                      subtitle: AppLocalizations.of(context)!.internetRadio,
                      isGradient: false,
                      onTap: () => _navigate(context, const RadioScreen()),
                    ),
                  ] else ...[  
                    _SpotifyLibraryTile(
                      icon: CupertinoIcons.heart_fill,
                      iconColor: const Color(0xFF8B5CF6),
                      title: AppLocalizations.of(context)!.likedSongs,
                      subtitle: AppLocalizations.of(context)!.playlist,
                      isGradient: true,
                      onTap: () => _navigate(context, const FavoritesScreen()),
                    ),
                    _SpotifyLibraryTile(
                      icon: CupertinoIcons.music_albums,
                      iconColor: const Color(0xFFEC4899),
                      title: AppLocalizations.of(context)!.allAlbums,
                      subtitle: AppLocalizations.of(context)!.filterAlbums,
                      isGradient: false,
                      onTap: () => _navigate(context, const AllAlbumsScreen()),
                    ),
                  ],
                ],
              ],
            ),
          ),

          Consumer<LibraryProvider>(
            builder: (context, libraryProvider, _) {
              final items = _getFilteredItems(context, libraryProvider);

              return SliverList(
                delegate: SliverChildBuilderDelegate((context, index) {
                  final item = items[index];
                  return _buildLibraryItem(context, item);
                }, childCount: items.length),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 150)),
        ],
      ),
    );
  }

  List<_LibraryItem> _getFilteredItems(
    BuildContext context,
    LibraryProvider provider,
  ) {
    final l10n = AppLocalizations.of(context)!;
    List<_LibraryItem> items = [];

    if (_selectedFilter == 'All' || _selectedFilter == 'Faves') {
      items.addAll(
        provider.playlists.map(
          (p) => _LibraryItem(
            type: 'Playlist',
            id: p.id,
            name: p.name,
            subtitle: l10n.songsCount(p.songCount ?? 0),
            coverArt: p.coverArt,
          ),
        ),
      );
    }

    if (_selectedFilter == 'All') {
      final albums = provider.isLocalOnlyMode
          ? provider.cachedAllAlbums.take(20).toList()
          : provider.recentAlbums.take(20).toList();
      items.addAll(
        albums.map(
          (a) => _LibraryItem(
            type: 'Album',
            id: a.id,
            name: a.name,
            subtitle: a.artistParticipants != null &&
                    a.artistParticipants!.isNotEmpty
                ? a.artistParticipants!.map((r) => r.name).join(', ')
                : (a.artist ?? ''),
            coverArt: a.coverArt,
          ),
        ),
      );
    }

    if (_selectedFilter == 'Faves') {
      final recent = provider.isLocalOnlyMode
          ? provider.cachedAllAlbums.take(10).toList()
          : provider.recentAlbums.take(10).toList();
      items.addAll(
        recent.map(
          (a) => _LibraryItem(
            type: 'Album',
            id: a.id,
            name: a.name,
            subtitle: a.artistParticipants != null &&
                    a.artistParticipants!.isNotEmpty
                ? a.artistParticipants!.map((r) => r.name).join(', ')
                : (a.artist ?? ''),
            coverArt: a.coverArt,
          ),
        ),
      );
    }

    if (_selectedFilter == 'Albums') {
      final albums = provider.isLocalOnlyMode
          ? provider.cachedAllAlbums
          : (provider.cachedAllAlbums.isNotEmpty
              ? provider.cachedAllAlbums
              : provider.recentAlbums);
      items.addAll(
        albums.map(
          (a) => _LibraryItem(
            type: 'Album',
            id: a.id,
            name: a.name,
            subtitle: a.artistParticipants != null &&
                    a.artistParticipants!.isNotEmpty
                ? a.artistParticipants!.map((r) => r.name).join(', ')
                : (a.artist ?? ''),
            coverArt: a.coverArt,
          ),
        ),
      );
    }

    if (_selectedFilter == 'Artists') {
      items.addAll(
        provider.artists.map(
          (a) => _LibraryItem(
            type: 'Artist',
            id: a.id,
            name: a.name,
            subtitle: l10n.albumsCount(a.albumCount ?? 0),
            coverArt: a.coverArt,
          ),
        ),
      );
    }

    if (_selectedFilter == 'Songs') {
      items.addAll(
        provider.cachedAllSongs.map(
          (s) => _LibraryItem(
            type: 'Song',
            id: s.id,
            name: s.title,
            subtitle: s.artist ?? '',
            coverArt: s.coverArt,
          ),
        ),
      );
    }

    return items;
  }

  Widget _buildLibraryItem(BuildContext context, _LibraryItem item) {
    final subsonicService = Provider.of<SubsonicService>(
      context,
      listen: false,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final coverArtUrl = item.coverArt != null
        ? (isLocalFilePath(item.coverArt)
              ? item.coverArt!
              : subsonicService.getCoverArtUrl(item.coverArt!, size: 120))
        : null;

    final String typeLabel = switch (item.type) {
      'Playlist' => l10n.filterPlaylists,
      'Album' => l10n.filterAlbums,
      'Artist' => l10n.filterArtists,
      'Song' => l10n.songs,
      _ => item.type,
    };

    final Widget artwork = ClipRRect(
      borderRadius: BorderRadius.circular(item.type == 'Artist' ? 28 : 4),
      child: SizedBox(
        width: 56,
        height: 56,
        child: coverArtUrl != null
            ? (isLocalFilePath(coverArtUrl)
                  ? Image.file(
                      File(coverArtUrl),
                      fit: BoxFit.cover,
                      errorBuilder: (ctx, err, stack) =>
                          _buildPlaceholder(item.type, isDark),
                    )
                  : CachedNetworkImage(
                      imageUrl: coverArtUrl,
                      fit: BoxFit.cover,
                      placeholder: (ctx, url) =>
                          Container(color: Colors.grey[800]),
                      errorWidget: (ctx, url, err) =>
                          _buildPlaceholder(item.type, isDark),
                    ))
            : _buildPlaceholder(item.type, isDark),
      ),
    );

    return InkWell(
      onTap: () => _openItem(context, item),
      onLongPress: item.type == 'Playlist'
          ? () => _showPlaylistOptionsSheet(context, item)
          : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            artwork,
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    item.name,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$typeLabel • ${item.subtitle}',
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black54,
                      fontSize: 13,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(String type, bool isDark) {
    IconData icon;
    switch (type) {
      case 'Playlist':
        icon = Icons.queue_music;
        break;
      case 'Album':
        icon = Icons.album;
        break;
      case 'Artist':
        icon = Icons.person;
        break;
      case 'Song':
        icon = Icons.music_note;
        break;
      default:
        icon = Icons.music_note;
    }

    return Container(
      color: isDark ? const Color(0xFF282828) : Colors.grey[300],
      child: Icon(icon, color: Colors.white54),
    );
  }

  void _openItem(BuildContext context, _LibraryItem item) {
    switch (item.type) {
      case 'Playlist':
        NavigationHelper.push(
          context,
          PlaylistScreen(playlistId: item.id, playlistName: item.name),
        );
        break;
      case 'Album':
        NavigationHelper.push(context, AlbumScreen(albumId: item.id));
        break;
      case 'Artist':
        NavigationHelper.push(context, ArtistScreen(artistId: item.id));
        break;
      case 'Song':
        final libraryProvider = Provider.of<LibraryProvider>(
          context,
          listen: false,
        );
        final playerProvider = Provider.of<PlayerProvider>(
          context,
          listen: false,
        );
        final songs = libraryProvider.cachedAllSongs;
        final index = songs.indexWhere((s) => s.id == item.id);
        if (index >= 0) {
          playerProvider.playSong(songs[index], playlist: songs, startIndex: index);
        }
        break;
    }
  }

  void _navigate(BuildContext context, Widget screen) {
    NavigationHelper.push(context, screen);
  }

  void _showDeletePlaylistDialog(BuildContext context, _LibraryItem item) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.deletePlaylist),
        content: Text(
          AppLocalizations.of(context)!.deletePlaylistConfirmation(item.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final libraryProvider = Provider.of<LibraryProvider>(
                context,
                listen: false,
              );
              try {
                await libraryProvider.deletePlaylist(item.id);
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(
                          context,
                        )!.playlistDeleted(item.name),
                      ),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppLocalizations.of(context)!.errorDeletingPlaylist(e),
                      ),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(AppLocalizations.of(context)!.delete),
          ),
        ],
      ),
    );
  }

  void _showPlaylistOptionsSheet(BuildContext context, _LibraryItem item) {
    if (_isPlaylistActionBusy) return;

    showPlaylistOptionsSheet(
      context,
      title: item.name,
      onDuplicate: () async {
        final messenger = ScaffoldMessenger.of(context);
        final libraryProvider =
            Provider.of<LibraryProvider>(context, listen: false);
        _isPlaylistActionBusy = true;
        try {
          final name = await libraryProvider.duplicatePlaylist(item.id);
          messenger.showSnackBar(
            SnackBar(
              content: Text('Duplicated as "$name"'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        } catch (e) {
          messenger.showSnackBar(
            SnackBar(
              content: const Text('Failed to duplicate playlist'),
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.red,
            ),
          );
        } finally {
          _isPlaylistActionBusy = false;
        }
      },
      onDelete: () {
        if (_isPlaylistActionBusy) return;
        Navigator.pop(context);
        _showDeletePlaylistDialog(context, item);
      },
      onDeleteWithSongs: () {
        if (_isPlaylistActionBusy) return;
        Navigator.pop(context);
        _showDeletePlaylistWithSongsDialog(context, item);
      },
    );
  }

  void _showDeletePlaylistWithSongsDialog(BuildContext context, _LibraryItem item) {
    showDialog(
      context: context,
      builder: (dialogContext) => _DeletePlaylistWithSongsDialog(
        name: item.name,
        onDelete: () async {
          final libraryProvider =
              Provider.of<LibraryProvider>(dialogContext, listen: false);
          _isPlaylistActionBusy = true;
          int? removed;
          bool succeeded = false;
          try {
            removed = await libraryProvider.deletePlaylistWithSongs(item.id);
            succeeded = true;
          } finally {
            _isPlaylistActionBusy = false;
          }
          return (succeeded, removed ?? 0);
        },
        onResult: (succeeded, removed) {
          final messenger = ScaffoldMessenger.of(context);
          if (succeeded) {
            messenger.showSnackBar(
              SnackBar(
                content: Text(
                  'Playlist deleted - $removed songs removed from library',
                ),
                behavior: SnackBarBehavior.floating,
              ),
            );
          } else {
            messenger.showSnackBar(
              SnackBar(
                content: const Text('Failed to delete playlist'),
                behavior: SnackBarBehavior.floating,
                backgroundColor: Colors.red,
              ),
            );
          }
        },
      ),
    );
  }

  void _showCreatePlaylistDialog(BuildContext context) {
    final controller = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.newPlaylist),
        content: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              hintText: AppLocalizations.of(context)!.playlistName,
              filled: true,
              fillColor: isDark
                  ? const Color(0xFF2C2C2E)
                  : const Color(0xFFF2F2F7),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () async {
              if (controller.text.trim().isNotEmpty) {
                final libraryProvider = Provider.of<LibraryProvider>(
                  context,
                  listen: false,
                );
                try {
                  await libraryProvider.createPlaylist(controller.text.trim());
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          AppLocalizations.of(
                            context,
                          )!.playlistCreated(controller.text),
                        ),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          AppLocalizations.of(
                            context,
                          )!.errorCreatingPlaylist(e),
                        ),
                        behavior: SnackBarBehavior.floating,
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              }
            },
            child: Text(AppLocalizations.of(context)!.create),
          ),
        ],
      ),
    );
  }

  void _showLibrarySearch(BuildContext context) {
    final libraryProvider = Provider.of<LibraryProvider>(
      context,
      listen: false,
    );
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showSearch(
      context: context,
      delegate: LibrarySearchDelegate(
        libraryProvider: libraryProvider,
        isDark: isDark,
      ),
    );
  }
}

class _LibraryItem {
  final String type;
  final String id;
  final String name;
  final String subtitle;
  final String? coverArt;

  _LibraryItem({
    required this.type,
    required this.id,
    required this.name,
    required this.subtitle,
    this.coverArt,
  });
}

class _DeletePlaylistWithSongsDialog extends StatefulWidget {
  final String name;
  final Future<(bool, int)> Function() onDelete;
  final void Function(bool succeeded, int removed) onResult;

  const _DeletePlaylistWithSongsDialog({
    required this.name,
    required this.onDelete,
    required this.onResult,
  });

  @override
  State<_DeletePlaylistWithSongsDialog> createState() =>
      _DeletePlaylistWithSongsDialogState();
}

class _DeletePlaylistWithSongsDialogState
    extends State<_DeletePlaylistWithSongsDialog> {
  bool _isDeleting = false;

  Future<void> _confirmDelete() async {
    if (_isDeleting) return;
    setState(() => _isDeleting = true);
    final result = await widget.onDelete();
    final succeeded = result.$1;
    final removed = result.$2;
    if (mounted) {
      Navigator.pop(context);
    }
    widget.onResult(succeeded, removed);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Delete & Remove Songs'),
      content: _isDeleting
          ? const Center(child: CircularProgressIndicator())
          : Text(
              'This will delete the playlist "${widget.name}" and permanently '
              'remove its songs from your library. The audio files will be '
              'deleted and cannot be recovered.',
            ),
      actions: [
        TextButton(
          onPressed: _isDeleting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: _isDeleting ? null : _confirmDelete,
          style: TextButton.styleFrom(foregroundColor: Colors.red),
          child: const Text('Delete & Remove'),
        ),
      ],
    );
  }
}

class _SpotifyLibraryTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final bool isGradient;
  final VoidCallback? onTap;

  const _SpotifyLibraryTile({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    this.isGradient = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Row(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(4),
                gradient: isGradient
                    ? LinearGradient(
                        colors: [iconColor.withValues(alpha: 0.8), iconColor],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : null,
                color: isGradient ? null : iconColor.withValues(alpha: 0.15),
              ),
              child: Icon(
                icon,
                color: isGradient ? Colors.white : iconColor,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black,
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: isDark ? Colors.white60 : Colors.black54,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
