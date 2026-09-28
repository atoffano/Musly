import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

Future<void> showPlaylistOptionsSheet(
  BuildContext context, {
  required String title,
  String subtitle = 'Playlist',
  String deleteLabel = 'Delete',
  VoidCallback? onDuplicate,
  VoidCallback? onDelete,
  VoidCallback? onDeleteWithSongs,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => PlaylistOptionsSheet(
      title: title,
      subtitle: subtitle,
      deleteLabel: deleteLabel,
      onDuplicate: onDuplicate,
      onDelete: onDelete,
      onDeleteWithSongs: onDeleteWithSongs,
    ),
  );
}

/// Single-action variant used for albums: no duplicate, no keep-songs option.
Future<void> showAlbumOptionsSheet(
  BuildContext context, {
  required String title,
  required VoidCallback onDelete,
}) {
  return showPlaylistOptionsSheet(
    context,
    title: title,
    subtitle: 'Album',
    deleteLabel: 'Delete Album',
    onDelete: onDelete,
  );
}

class PlaylistOptionsSheet extends StatelessWidget {
  final String title;
  final String subtitle;
  final String deleteLabel;
  final VoidCallback? onDuplicate;
  final VoidCallback? onDelete;
  final VoidCallback? onDeleteWithSongs;

  const PlaylistOptionsSheet({
    super.key,
    required this.title,
    this.subtitle = 'Playlist',
    this.deleteLabel = 'Delete',
    this.onDuplicate,
    this.onDelete,
    this.onDeleteWithSongs,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 16,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark ? AppTheme.darkDivider : AppTheme.lightDivider,
                  borderRadius: BorderRadius.circular(2.5),
                ),
              ),
              const SizedBox(height: 16),

              // Playlist Header Card
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkCard : AppTheme.lightBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark
                          ? Colors.white10
                          : Colors.black.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 18,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: isDark ? Colors.white70 : Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              if (onDuplicate != null)
                ListTile(
                  leading: Icon(
                    CupertinoIcons.doc_on_doc,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                  title: const Text('Duplicate'),
                  onTap: onDuplicate,
                ),

              if (onDelete != null)
                ListTile(
                  leading: const Icon(
                    CupertinoIcons.trash,
                    color: Colors.red,
                  ),
                  title: Text(
                    deleteLabel,
                    style: const TextStyle(color: Colors.red),
                  ),
                  onTap: onDelete,
                ),

              if (onDeleteWithSongs != null)
                ListTile(
                  leading: const Icon(
                    CupertinoIcons.trash_fill,
                    color: Colors.red,
                  ),
                  title: const Text(
                    'Delete & Remove Songs',
                    style: TextStyle(color: Colors.red),
                  ),
                  onTap: onDeleteWithSongs,
                ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
