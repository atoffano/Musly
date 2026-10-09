import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../models/song.dart';
import '../../providers/player_provider.dart';
import '../../utils/formatters.dart';
import 'album_artwork.dart';
import 'animated_equalizer.dart';
import '../modals/song_options_modal.dart';

import 'package:musly/services/tv_detection_service.dart';
import 'package:musly/widgets/navigation/tv_remote_scope.dart';
import 'swipeable_song_tile.dart';
import 'package:flutter/cupertino.dart';

class SongTile extends StatelessWidget {
  final Song song;
  final List<Song>? playlist;
  final int? index;
  final bool showArtwork;
  final bool showArtist;
  final bool showAlbum;
  final bool showDuration;
  final bool showTrackNumber;
  final bool enableSwipeToQueue;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  const SongTile({
    super.key,
    required this.song,
    this.playlist,
    this.index,
    this.showArtwork = true,
    this.showArtist = true,
    this.showAlbum = false,
    this.showDuration = false,
    this.showTrackNumber = false,
    this.enableSwipeToQueue = true,
    this.onTap,
    this.onLongPress,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final isTv = Provider.of<TvDetectionService>(context).isTvMode;

    return Consumer<PlayerProvider>(
      builder: (context, playerProvider, child) {
        final isPlaying = playerProvider.currentSong?.id == song.id;

        final actualOnTap = onTap ?? () => _playSong(context);
        final actualOnLongPress = onLongPress ?? () => _showOptions(context);

        final tile = ListTile(
          dense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          leading: _buildLeading(context, isPlaying),
          title: Text(
            song.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: isPlaying ? FontWeight.bold : FontWeight.w500,
              color: isPlaying
                  ? theme.colorScheme.primary
                  : (isDark ? Colors.white : Colors.black87),
            ),
          ),
          subtitle: _buildSubtitle(context),
          trailing: trailing ?? _buildTrailing(context),
          onTap: isTv ? null : actualOnTap,
          onLongPress: isTv ? null : actualOnLongPress,
        );

        Widget finalTile = tile;
        if (enableSwipeToQueue) {
          finalTile = SwipeableSongTile(
            onSwipeToQueue: () {
              playerProvider.addToQueue(song);
              ScaffoldMessenger.of(context).hideCurrentSnackBar();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Row(
                    children: [
                      const Icon(CupertinoIcons.text_badge_plus,
                          color: Colors.white, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '"${song.title}" added to queue',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  duration: const Duration(seconds: 2),
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
              );
            },
            child: tile,
          );
        }

        if (isTv) {
          return TvFocusableCard(
            onTap: actualOnTap,
            onLongPress: actualOnLongPress,
            borderRadius: BorderRadius.circular(8),
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: finalTile,
          );
        }

        return finalTile;
      },
    );
  }

  Widget? _buildLeading(BuildContext context, bool isPlaying) {
    if (isPlaying) {
      return SizedBox(
        width: 44,
        height: 44,
        child: Center(
          child: AnimatedEqualizer(
            color: Theme.of(context).colorScheme.primary,
            isPlaying: true,
          ),
        ),
      );
    }

    if (showTrackNumber && song.track != null) {
      return SizedBox(
        width: 32,
        height: 44,
        child: Center(
          child: Text(
            '${song.track}',
            style: const TextStyle(color: Colors.grey, fontSize: 14),
          ),
        ),
      );
    }

    if (showArtwork) {
      return AlbumArtwork(
        coverArt: song.coverArt,
        size: 44,
        borderRadius: 6,
      );
    }

    return null;
  }

  Widget? _buildSubtitle(BuildContext context) {
    final parts = <String>[];
    if (showArtist && song.artist != null && song.artist!.isNotEmpty) {
      parts.add(song.artist!);
    }
    if (showAlbum && song.album != null && song.album!.isNotEmpty) {
      parts.add(song.album!);
    }

    if (parts.isEmpty) return null;

    return Text(
      parts.join(' • '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(fontSize: 12, color: Colors.grey),
    );
  }

  bool _canToggleLibrarySaved(Song song) {
    return song.isYouTube ||
        (song.sourceId != null && song.sourceId!.isNotEmpty) ||
        song.id.startsWith('yt:');
  }

  Widget _buildTrailing(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_canToggleLibrarySaved(song))
          Selector<PlayerProvider, ({bool saved, bool busy})>(
            selector: (_, provider) => (
              saved: provider.isYouTubeSaved(song),
              busy: provider.isYouTubeSaveBusy(song),
            ),
            builder: (context, state, _) {
              return Padding(
                padding: EdgeInsets.only(right: state.busy ? 12 : 4),
                child: state.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        visualDensity: VisualDensity.compact,
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                        padding: EdgeInsets.zero,
                        tooltip: state.saved
                            ? 'Remove from library'
                            : 'Add to library',
                        onPressed: () async {
                          final playerProvider = Provider.of<PlayerProvider>(
                            context,
                            listen: false,
                          );
                          final messenger = ScaffoldMessenger.of(context);

                          try {
                            await playerProvider.toggleYouTubeSaved(song);
                            if (!context.mounted) {
                              return;
                            }
                            final nowSaved =
                                playerProvider.isYouTubeSaved(song);
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(
                                  nowSaved
                                      ? 'Saving to library started'
                                      : 'Removed from library',
                                ),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          } catch (e) {
                            if (!context.mounted) {
                              return;
                            }
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Save action failed: $e'),
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          }
                        },
                        icon: Icon(
                          state.saved
                              ? Icons.check_circle_rounded
                              : Icons.add_circle_outline_rounded,
                          size: 18,
                          color: state.saved
                              ? const Color(0xFF1DB954)
                              : Theme.of(context).textTheme.bodySmall?.color,
                        ),
                      ),
              );
            },
          ),
        if (showDuration && song.duration != null && song.duration! > 0) ...[
          Text(
            FormatUtils.formatSeconds(song.duration),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          const SizedBox(width: 8),
        ],
        IconButton(
          icon: const Icon(Icons.more_horiz),
          iconSize: 20,
          color: Theme.of(context).textTheme.bodySmall?.color,
          onPressed: () => _showOptions(context),
        ),
      ],
    );
  }

  void _playSong(BuildContext context) {
    HapticFeedback.selectionClick();
    final playerProvider = Provider.of<PlayerProvider>(context, listen: false);
    playerProvider.playSong(song, playlist: playlist, startIndex: index);
  }

  void _showOptions(BuildContext context) {
    SongOptionsModal.show(context, song);
  }
}
