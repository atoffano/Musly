import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../providers/player_provider.dart';
import '../screens/pipeline_logs_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/spotify_migration_screen.dart';
import '../services/musly_backend_service.dart';
import '../services/subsonic_service.dart';
import '../theme/app_theme.dart';
import '../utils/navigation_helper.dart';
import 'user_profile_avatar.dart';

void showSettingsSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (context) => const SettingsSheet(),
  );
}

class SettingsSheet extends StatefulWidget {
  const SettingsSheet({super.key});

  @override
  State<SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<SettingsSheet> {
  UserProfile? _userProfile;

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    final subsonic = Provider.of<SubsonicService>(context, listen: false);
    final bridgeUrl = subsonic.bridgeUrl ?? '';
    if (bridgeUrl.isNotEmpty) {
      final profile = await MuslyBackendService().getUserProfile(bridgeUrl);
      if (mounted && profile != null) {
        setState(() {
          _userProfile = profile;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final authProvider = Provider.of<AuthProvider>(context);
    final l10n = AppLocalizations.of(context);

    final rawName = _userProfile?.displayName.trim();
    final displayName = (rawName != null && rawName.isNotEmpty)
        ? rawName
        : (authProvider.config?.username.isNotEmpty == true
            ? authProvider.config!.username
            : 'Aki');

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

              // Profile Card Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? AppTheme.darkCard : AppTheme.lightBackground,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isDark ? Colors.white10 : Colors.black.withValues(alpha: 0.05),
                    ),
                  ),
                  child: Row(
                    children: [
                      const UserProfileAvatar(
                        size: 56,
                        showBorder: true,
                        interactive: false,
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: theme.textTheme.titleLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: authProvider.state == AuthState.offlineMode
                                        ? Colors.orange
                                        : Colors.green,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    authProvider.state == AuthState.offlineMode
                                        ? (l10n?.offlineMode ?? 'Offline Mode')
                                        : (authProvider.config?.serverUrl ??
                                            l10n?.connected ??
                                            'Connected'),
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: isDark ? Colors.white70 : Colors.black54,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 8),

              ListTile(
                leading: Icon(
                  CupertinoIcons.gear_alt,
                  color: isDark ? Colors.white : Colors.black87,
                ),
                title: Text(l10n?.settingsTitle ?? 'Settings'),
                trailing: Icon(
                  CupertinoIcons.chevron_forward,
                  size: 18,
                  color: isDark ? AppTheme.darkDivider : AppTheme.lightDivider,
                ),
                onTap: () {
                  Navigator.pop(context);
                  NavigationHelper.push(context, const SettingsScreen());
                },
              ),

              ListTile(
                leading: const Icon(
                  CupertinoIcons.arrow_down_doc,
                  color: Color(0xFF1DB954),
                ),
                title: const Text('Import from Spotify'),
                subtitle: const Text('Playlists, Liked Songs & Scrobbles'),
                trailing: Icon(
                  CupertinoIcons.chevron_forward,
                  size: 18,
                  color: isDark ? AppTheme.darkDivider : AppTheme.lightDivider,
                ),
                onTap: () {
                  Navigator.pop(context);
                  final subsonic = Provider.of<SubsonicService>(context, listen: false);
                  NavigationHelper.push(
                    context,
                    SpotifyMigrationScreen(bridgeUrl: subsonic.bridgeUrl),
                  );
                },
              ),

              ListTile(
                leading: Icon(
                  CupertinoIcons.doc_text_search,
                  color: isDark ? Colors.white70 : Colors.black54,
                ),
                title: const Text('Pipeline Logs'),
                trailing: Icon(
                  CupertinoIcons.chevron_forward,
                  size: 18,
                  color: isDark ? AppTheme.darkDivider : AppTheme.lightDivider,
                ),
                onTap: () {
                  Navigator.pop(context);
                  final subsonic = Provider.of<SubsonicService>(context, listen: false);
                  NavigationHelper.push(
                    context,
                    PipelineLogsScreen(bridgeUrl: subsonic.bridgeUrl),
                  );
                },
              ),

              ListTile(
                leading: const Icon(
                  CupertinoIcons.arrow_right_square,
                  color: Colors.red,
                ),
                title: Text(
                  l10n?.logout ?? 'Logout',
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await Provider.of<PlayerProvider>(context, listen: false).stop();
                  await authProvider.logout();
                },
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
