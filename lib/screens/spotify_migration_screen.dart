import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/musly_backend_service.dart';
import '../services/subsonic_service.dart';
import '../theme/app_theme.dart';

class SpotifyMigrationScreen extends StatefulWidget {
  final String? bridgeUrl;

  const SpotifyMigrationScreen({super.key, this.bridgeUrl});

  @override
  State<SpotifyMigrationScreen> createState() => _SpotifyMigrationScreenState();
}

class _SpotifyMigrationScreenState extends State<SpotifyMigrationScreen> {
  final MuslyBackendService _backend = MuslyBackendService();
  final TextEditingController _urlInputController = TextEditingController();
  final TextEditingController _dumpAccountPathController = TextEditingController();
  final TextEditingController _dumpHistoryPathController = TextEditingController();
  final ScrollController _logScrollController = ScrollController();

  int _importMode = 0; // 0: Fast URL Route, 1: Complete GDPR Dump Route
  int _currentStep = 0; // 0: Setup / Preview, 2: In-flight Progress
  bool _isLoading = false;
  String? _errorMessage;

  // ---------------------------------------------------------------------------
  // Fast Route State (Public URLs)
  // ---------------------------------------------------------------------------
  bool _urlStarLikedSongs = true;
  bool _urlCreatePlaylists = true;
  bool _isPreviewingUrls = false;
  List<Map<String, dynamic>> _urlPreviewEntities = [];
  List<String> _urlPreviewErrors = [];
  int _urlTotalTracks = 0;

  // ---------------------------------------------------------------------------
  // Slow Route State (GDPR Account Dump)
  // ---------------------------------------------------------------------------
  bool _isInspectingDump = false;
  Map<String, dynamic>? _dumpSummary;
  List<Map<String, dynamic>> _dumpSources = [];
  bool _dumpImportLibrary = true;
  bool _dumpImportPlaylists = true;
  final Set<String> _dumpSelectedPlaylists = {};
  bool _dumpImportScrobbles = true;
  bool _dumpSyncListenbrainz = false;
  bool _dumpSyncLastfm = false;

  // ---------------------------------------------------------------------------
  // Shared Migration Progress State
  // ---------------------------------------------------------------------------
  Timer? _statusPollTimer;
  Map<String, dynamic>? _migrationStatus;

  bool get _isDark => Theme.of(context).brightness == Brightness.dark;

  String _getEffectiveBridgeUrl() {
    if (widget.bridgeUrl?.isNotEmpty == true) return widget.bridgeUrl!;
    return Provider.of<SubsonicService>(context, listen: false).bridgeUrl ?? '';
  }

  @override
  void initState() {
    super.initState();
    _restoreMigrationState();
  }

  @override
  void dispose() {
    _statusPollTimer?.cancel();
    _urlInputController.dispose();
    _dumpAccountPathController.dispose();
    _dumpHistoryPathController.dispose();
    _logScrollController.dispose();
    super.dispose();
  }

  Future<void> _restoreMigrationState() async {
    final bridgeUrl = _getEffectiveBridgeUrl();
    if (bridgeUrl.isEmpty) return;

    try {
      final status = await _backend.getSpotifyMigrationStatus(bridgeUrl);
      if (!mounted) return;
      final stateStr = status['status']?.toString();
      if (stateStr == 'running') {
        setState(() {
          _currentStep = 2;
          _migrationStatus = status;
        });
        _startStatusPolling();
      } else if (stateStr == 'completed' || stateStr == 'failed' || stateStr == 'cancelled') {
        // Restore the final state of the last run (stats, playlists, logs are
        // kept in memory by the backend). No polling for terminal states.
        setState(() {
          _currentStep = 2;
          _migrationStatus = status;
        });
      }
      // idle (or unknown) -> stay on step 1
    } catch (_) {}
  }

  void _startStatusPolling() {
    _statusPollTimer?.cancel();
    _statusPollTimer = Timer.periodic(const Duration(milliseconds: 1200), (_) async {
      final bridgeUrl = _getEffectiveBridgeUrl();
      if (bridgeUrl.isEmpty) return;

      try {
        final status = await _backend.getSpotifyMigrationStatus(bridgeUrl);
        if (mounted) {
          setState(() {
            _migrationStatus = status;
          });

          // Auto-scroll log console
          if (_logScrollController.hasClients) {
            _logScrollController.animateTo(
              _logScrollController.position.maxScrollExtent,
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
            );
          }

          if (status['status'] != 'running') {
            _statusPollTimer?.cancel();
          }
        }
      } catch (_) {}
    });
  }

  // ===========================================================================
  // Fast Route Actions (URLs)
  // ===========================================================================

  Future<void> _previewUrls() async {
    final urlsText = _urlInputController.text.trim();
    if (urlsText.isEmpty) {
      setState(() => _errorMessage = 'Please enter at least one Spotify playlist or album URL.');
      return;
    }

    final bridgeUrl = _getEffectiveBridgeUrl();
    if (bridgeUrl.isEmpty) {
      setState(() => _errorMessage = 'Bridge URL is not configured. Check your server settings.');
      return;
    }

    setState(() {
      _isPreviewingUrls = true;
      _errorMessage = null;
      _urlPreviewEntities = [];
      _urlPreviewErrors = [];
    });

    try {
      final res = await _backend.previewSpotifyPublicUrls(bridgeUrl, urlsText);
      if (mounted) {
        setState(() {
          _isPreviewingUrls = false;
          final entities = (res['entities'] as List?) ?? [];
          final errors = (res['errors'] as List?) ?? [];
          _urlPreviewEntities = entities.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
          _urlPreviewErrors = errors.map((e) => e.toString()).toList();
          _urlTotalTracks = res['totalTracks'] is int ? res['totalTracks'] : 0;

          if (_urlPreviewEntities.isEmpty && _urlPreviewErrors.isNotEmpty) {
            _errorMessage = _urlPreviewErrors.join('\n');
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isPreviewingUrls = false;
          _errorMessage = 'Failed to preview URLs: $e';
        });
      }
    }
  }

  Future<void> _startUrlMigration() async {
    final urlsText = _urlInputController.text.trim();
    if (urlsText.isEmpty) return;

    final bridgeUrl = _getEffectiveBridgeUrl();
    if (bridgeUrl.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _backend.startSpotifyUrlMigration(
        bridgeUrl,
        urls: urlsText,
        starLikedSongs: _urlStarLikedSongs,
        createPlaylists: _urlCreatePlaylists,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _currentStep = 2;
          _migrationStatus = res['job'] is Map ? Map<String, dynamic>.from(res['job']) : null;
        });
        _startStatusPolling();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to start URL migration: $e';
        });
      }
    }
  }

  // ===========================================================================
  // Slow Route Actions (GDPR Dump)
  // ===========================================================================

  List<String> _collectDumpPaths() {
    return [
      _dumpAccountPathController.text.trim(),
      _dumpHistoryPathController.text.trim(),
    ].where((p) => p.isNotEmpty).toList();
  }

  Future<void> _inspectDump() async {
    final paths = _collectDumpPaths();
    if (paths.isEmpty) {
      setState(() =>
          _errorMessage = 'Enter at least one dump path: Account Data and/or Extended Streaming History.');
      return;
    }

    final bridgeUrl = _getEffectiveBridgeUrl();
    if (bridgeUrl.isEmpty) {
      setState(() => _errorMessage = 'Bridge URL is not configured.');
      return;
    }

    setState(() {
      _isInspectingDump = true;
      _errorMessage = null;
    });

    try {
      final res = await _backend.previewSpotifyDump(bridgeUrl, paths: paths);
      if (mounted) {
        setState(() {
          _isInspectingDump = false;
          _dumpSources = (res['sources'] as List?)
                  ?.whereType<Map>()
                  .map((s) => Map<String, dynamic>.from(s))
                  .toList() ??
              [];
          // Merged summary drives the stats grid & playlist checkboxes;
          // fall back to the legacy single-source summary when absent.
          Map<String, dynamic>? summary;
          if (res['merged'] is Map) {
            summary = Map<String, dynamic>.from(res['merged']);
          } else if (res['summary'] is Map) {
            summary = Map<String, dynamic>.from(res['summary']);
          }
          _dumpSummary = summary;
          // By default, select all playlists
          if (_dumpSummary != null && _dumpSummary!['playlists'] is List) {
            _dumpSelectedPlaylists.clear();
            for (var p in _dumpSummary!['playlists']) {
              if (p is Map && p['name'] != null) {
                _dumpSelectedPlaylists.add(p['name'].toString());
              }
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isInspectingDump = false;
          _errorMessage = 'Failed to inspect Spotify dump: $e';
        });
      }
    }
  }

  Future<void> _startDumpMigration() async {
    final paths = _collectDumpPaths();
    if (paths.isEmpty) {
      setState(() =>
          _errorMessage = 'Enter at least one dump path: Account Data and/or Extended Streaming History.');
      return;
    }

    final bridgeUrl = _getEffectiveBridgeUrl();
    if (bridgeUrl.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await _backend.startSpotifyDumpMigration(
        bridgeUrl,
        paths: paths,
        importLibrary: _dumpImportLibrary,
        importPlaylists: _dumpImportPlaylists,
        selectedPlaylists: _dumpSelectedPlaylists.toList(),
        importScrobbles: _dumpImportScrobbles,
        syncScrobblesListenbrainz: _dumpSyncListenbrainz,
        syncScrobblesLastfm: _dumpSyncLastfm,
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _currentStep = 2;
          _migrationStatus = res['job'] is Map ? Map<String, dynamic>.from(res['job']) : null;
        });
        _startStatusPolling();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to start dump migration: $e';
        });
      }
    }
  }

  Future<void> _cancelMigration() async {
    final bridgeUrl = _getEffectiveBridgeUrl();
    if (bridgeUrl.isEmpty) return;

    try {
      await _backend.cancelSpotifyMigration(bridgeUrl);
    } catch (_) {}
  }

  // ===========================================================================
  // UI Builder
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
      appBar: AppBar(
        title: const Text('Spotify Migration', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
        centerTitle: false,
        backgroundColor: _isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      body: SafeArea(
        child: Column(
          children: [
            if (_currentStep < 2) _buildModeSelector(),
            if (_errorMessage != null) _buildErrorBanner(_errorMessage!),
            Expanded(
              child: _currentStep == 2
                  ? _buildProgressDashboard()
                  : (_importMode == 0 ? _buildFastUrlView() : _buildSlowDumpView()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeSelector() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _isDark ? AppTheme.darkSurface : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: _isDark ? AppTheme.darkDivider : AppTheme.lightDivider,
          width: 0.5,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _buildModeTab(
              mode: 0,
              title: '⚡ Fast Route',
              subtitle: 'Public Playlist Links',
              icon: CupertinoIcons.link,
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: _buildModeTab(
              mode: 1,
              title: '📦 Complete Route',
              subtitle: 'GDPR Data Dump',
              icon: CupertinoIcons.archivebox_fill,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeTab({
    required int mode,
    required String title,
    required String subtitle,
    required IconData icon,
  }) {
    final isSelected = _importMode == mode;
    return InkWell(
      onTap: () {
        if (_importMode != mode) {
          setState(() {
            _importMode = mode;
            _errorMessage = null;
          });
        }
      },
      borderRadius: BorderRadius.circular(10),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (_isDark ? const Color(0xFF282828) : Colors.white)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.12),
                    blurRadius: 6,
                    offset: const Offset(0, 2),
                  )
                ]
              : null,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              icon,
              size: 20,
              color: isSelected
                  ? AppTheme.spotifyGreen
                  : (_isDark ? Colors.grey.shade400 : Colors.grey.shade600),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isSelected
                          ? (_isDark ? Colors.white : Colors.black87)
                          : (_isDark ? Colors.grey.shade400 : Colors.grey.shade700),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: isSelected
                          ? AppTheme.spotifyGreen
                          : (_isDark ? Colors.grey.shade500 : Colors.grey.shade600),
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

  Widget _buildErrorBanner(String message) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.redAccent, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.redAccent, fontSize: 12.5),
            ),
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.xmark, size: 14, color: Colors.redAccent),
            onPressed: () => setState(() => _errorMessage = null),
            visualDensity: VisualDensity.compact,
            padding: EdgeInsets.zero,
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 1. Fast Route View (Public URLs & 15-second Desktop Trick)
  // ===========================================================================

  Widget _buildFastUrlView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        // 15-second Liked Songs Trick Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: _isDark
                  ? [const Color(0xFF1B382B), const Color(0xFF182A22)]
                  : [const Color(0xFFE8F5E9), const Color(0xFFC8E6C9)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AppTheme.spotifyGreen.withOpacity(0.4)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(CupertinoIcons.lightbulb_fill, color: AppTheme.spotifyGreen, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    '15-Second Trick for "Liked Songs"',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: AppTheme.spotifyGreen),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Want to import your Liked Songs instantly without waiting weeks for GDPR data?\n'
                '1. Open the Spotify Desktop app and select Liked Songs.\n'
                '2. Press Ctrl+A (Cmd+A on macOS) to select all songs.\n'
                '3. Right-click ➔ Add to playlist ➔ New playlist.\n'
                '4. Right-click the new playlist ➔ Share ➔ Copy link to playlist.\n'
                '5. Paste the link into the box below!',
                style: TextStyle(
                  fontSize: 12,
                  height: 1.45,
                  color: _isDark ? Colors.grey.shade300 : Colors.grey.shade800,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // URL Input Box
        Text(
          'Spotify Playlist or Album URLs',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
            color: _isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        TextField(
          controller: _urlInputController,
          maxLines: 4,
          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: 'https://open.spotify.com/playlist/...\nhttps://open.spotify.com/album/...\n(One URL per line)',
            hintStyle: TextStyle(fontSize: 12, color: _isDark ? Colors.grey.shade600 : Colors.grey.shade400),
            filled: true,
            fillColor: _isDark ? AppTheme.darkSurface : Colors.grey.shade100,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.all(12),
          ),
        ),

        const SizedBox(height: 10),

        Row(
          children: [
            ElevatedButton.icon(
              onPressed: _isPreviewingUrls ? null : _previewUrls,
              icon: _isPreviewingUrls
                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                  : const Icon(CupertinoIcons.search, size: 16),
              label: Text(_isPreviewingUrls ? 'Resolving...' : 'Preview URLs'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.spotifyGreen,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () async {
                final data = await Clipboard.getData('text/plain');
                if (data?.text != null) {
                  _urlInputController.text = data!.text!;
                  _previewUrls();
                }
              },
              icon: const Icon(CupertinoIcons.doc_on_clipboard, size: 15),
              label: const Text('Paste from Clipboard'),
            ),
          ],
        ),

        if (_urlPreviewEntities.isNotEmpty) ...[
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _isDark ? AppTheme.darkSurface : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _isDark ? AppTheme.darkDivider : AppTheme.lightDivider),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Ready to Import (${_urlPreviewEntities.length} playlists/albums)',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                    Text(
                      '$_urlTotalTracks tracks',
                      style: const TextStyle(color: AppTheme.spotifyGreen, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _urlPreviewEntities.map((e) {
                    final name = e['name']?.toString() ?? 'Playlist';
                    final trackCount = (e['tracks'] as List?)?.length ?? 0;
                    return Chip(
                      label: Text('$name ($trackCount tracks)', style: const TextStyle(fontSize: 11)),
                      backgroundColor: _isDark ? const Color(0xFF252525) : Colors.grey.shade200,
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          CheckboxListTile(
            title: const Text('Star as Liked Songs in Navidrome', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: const Text('Automatically adds songs into your favorites', style: TextStyle(fontSize: 11)),
            value: _urlStarLikedSongs,
            onChanged: (val) => setState(() => _urlStarLikedSongs = val ?? true),
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            activeColor: AppTheme.spotifyGreen,
          ),
          CheckboxListTile(
            title: const Text('Reconstruct Navidrome Playlists', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: const Text('Creates playlist entities in your library', style: TextStyle(fontSize: 11)),
            value: _urlCreatePlaylists,
            onChanged: (val) => setState(() => _urlCreatePlaylists = val ?? true),
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            activeColor: AppTheme.spotifyGreen,
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _startUrlMigration,
              icon: const Icon(CupertinoIcons.play_arrow_solid, size: 18),
              label: Text('Start Fast Migration ($_urlTotalTracks Songs)', style: const TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.spotifyGreen,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ===========================================================================
  // 2. Slow Route View (GDPR Account Data Dump)
  // ===========================================================================

  Widget _buildSlowDumpView() {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
      children: [
        // Step-by-Step GDPR Guidance Card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _isDark ? AppTheme.darkSurface : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _isDark ? AppTheme.darkDivider : AppTheme.lightDivider),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(CupertinoIcons.info_circle_fill, color: Colors.blueAccent, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'How to get your Spotify GDPR Export',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '1. Go to spotify.com/account/privacy in your web browser.\n'
                '2. Scroll down to "Download your data" and select "Account data" (and optionally "Extended streaming history").\n'
                '3. Confirm via the email Spotify sends you.\n'
                '4. You will receive a ZIP file containing YourLibrary.json, Playlist1.json, and StreamingHistory*.json.\n'
                '5. Place it on your server or enter its path below!',
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.45,
                  color: _isDark ? Colors.grey.shade300 : Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Dump Path Inputs (one or both zips / folders)
        Text(
          'Spotify GDPR Dump (zip or folder)',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13.5,
            color: _isDark ? Colors.white : Colors.black87,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Account Data (zip or folder)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _isDark ? Colors.grey.shade300 : Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _dumpAccountPathController,
          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: '/home/aki/docker/music-pipeline/my_spotify_account_data.zip',
            helperText: 'Identity/profile, liked songs (YourLibrary), playlists, recent history.',
            helperMaxLines: 2,
            filled: true,
            fillColor: _isDark ? AppTheme.darkSurface : Colors.grey.shade100,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Extended Streaming History (zip or folder)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: _isDark ? Colors.grey.shade300 : Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 4),
        TextField(
          controller: _dumpHistoryPathController,
          style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
          decoration: InputDecoration(
            hintText: '/home/aki/docker/music-pipeline/my_spotify_streaming_history.zip',
            helperText: 'Full streaming backlog used to rebuild scrobbles.',
            helperMaxLines: 2,
            filled: true,
            fillColor: _isDark ? AppTheme.darkSurface : Colors.grey.shade100,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Tip: the two zips can be run at once or independently — the server remembers which sources were already migrated, so adding the second one later only processes what is new.',
          style: TextStyle(
            fontSize: 11,
            height: 1.4,
            color: _isDark ? Colors.grey.shade500 : Colors.grey.shade600,
          ),
        ),

        const SizedBox(height: 10),

        ElevatedButton.icon(
          onPressed: _isInspectingDump ? null : _inspectDump,
          icon: _isInspectingDump
              ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Icon(CupertinoIcons.search, size: 16),
          label: Text(_isInspectingDump ? 'Scanning Dump Files...' : 'Inspect Dump Data'),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppTheme.spotifyGreen,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),

        if (_dumpSources.isNotEmpty) ...[
          const SizedBox(height: 20),
          // Per-Source Cards (one per detected dump part)
          Text(
            'Detected Sources (${_dumpSources.length})',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _isDark ? Colors.white : Colors.black87),
          ),
          const SizedBox(height: 8),
          for (final source in _dumpSources) _buildSourceCard(source),
        ],

        if (_dumpSummary != null) ...[
          const SizedBox(height: 20),
          // Statistics Grid
          Row(
            children: [
              Expanded(
                child: _buildSummaryMetric(
                  icon: CupertinoIcons.heart_fill,
                  color: Colors.redAccent,
                  title: 'Liked Songs',
                  count: _dumpSummary!['libraryTracksCount'] ?? 0,
                  caption: 'from YourLibrary.json',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSummaryMetric(
                  icon: CupertinoIcons.music_albums,
                  color: Colors.tealAccent,
                  title: 'Playlists',
                  count: _dumpSummary!['playlistsCount'] ?? 0,
                  caption: 'from Playlist*.json',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildSummaryMetric(
                  icon: CupertinoIcons.guitars,
                  color: Colors.purpleAccent,
                  title: 'Saved Albums',
                  count: _dumpSummary!['libraryAlbumsCount'] ?? 0,
                  caption: 'album catalog',
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSummaryMetric(
                  icon: CupertinoIcons.waveform_path_ecg,
                  color: Colors.orangeAccent,
                  title: 'Scrobbles',
                  count: _dumpSummary!['scrobblesCount'] ?? 0,
                  caption: 'StreamingHistory*.json',
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Ingestion Options & Checkboxes
          Text('Ingestion Options', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: _isDark ? Colors.white : Colors.black87)),
          const SizedBox(height: 6),

          CheckboxListTile(
            title: const Text('Import Liked Songs', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text('Ingest & star ${_dumpSummary!['libraryTracksCount'] ?? 0} tracks in Navidrome', style: const TextStyle(fontSize: 11)),
            value: _dumpImportLibrary,
            onChanged: (val) => setState(() => _dumpImportLibrary = val ?? true),
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            activeColor: AppTheme.spotifyGreen,
          ),

          CheckboxListTile(
            title: const Text('Reconstruct Playlists', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text('Rebuild ${_dumpSelectedPlaylists.length} of ${_dumpSummary!['playlistsCount'] ?? 0} playlists', style: const TextStyle(fontSize: 11)),
            value: _dumpImportPlaylists,
            onChanged: (val) => setState(() => _dumpImportPlaylists = val ?? true),
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            activeColor: AppTheme.spotifyGreen,
          ),

          if (_dumpImportPlaylists && _dumpSummary!['playlists'] is List) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: (_dumpSummary!['playlists'] as List).map((p) {
                  if (p is! Map) return const SizedBox.shrink();
                  final name = p['name']?.toString() ?? 'Playlist';
                  final count = p['trackCount'] ?? 0;
                  final isSelected = _dumpSelectedPlaylists.contains(name);
                  return FilterChip(
                    label: Text('$name ($count)', style: const TextStyle(fontSize: 11)),
                    selected: isSelected,
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _dumpSelectedPlaylists.add(name);
                        } else {
                          _dumpSelectedPlaylists.remove(name);
                        }
                      });
                    },
                    selectedColor: AppTheme.spotifyGreen.withOpacity(0.3),
                    checkmarkColor: AppTheme.spotifyGreen,
                  );
                }).toList(),
              ),
            ),
          ],

          CheckboxListTile(
            title: const Text('Ingest Scrobbles into Scrobble Lake', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            subtitle: Text('Store ${_dumpSummary!['scrobblesCount'] ?? 0} plays into SQLite ledger and Parquet lake', style: const TextStyle(fontSize: 11)),
            value: _dumpImportScrobbles,
            onChanged: (val) => setState(() => _dumpImportScrobbles = val ?? true),
            controlAffinity: ListTileControlAffinity.leading,
            dense: true,
            activeColor: AppTheme.spotifyGreen,
          ),

          if (_dumpImportScrobbles) ...[
            Padding(
              padding: const EdgeInsets.only(left: 32),
              child: Column(
                children: [
                  CheckboxListTile(
                    title: const Text('Sync with ListenBrainz', style: TextStyle(fontSize: 12)),
                    subtitle: const Text(
                      'Off by default: your scrobble history is already uploaded. Enable only to push scrobbles to ListenBrainz.',
                      style: TextStyle(fontSize: 10.5),
                    ),
                    value: _dumpSyncListenbrainz,
                    onChanged: (val) => setState(() => _dumpSyncListenbrainz = val ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    activeColor: AppTheme.spotifyGreen,
                  ),
                  CheckboxListTile(
                    title: const Text('Sync with Last.fm', style: TextStyle(fontSize: 12)),
                    subtitle: const Text(
                      'Off by default: your scrobble history is already uploaded. Enable only to push scrobbles to Last.fm.',
                      style: TextStyle(fontSize: 10.5),
                    ),
                    value: _dumpSyncLastfm,
                    onChanged: (val) => setState(() => _dumpSyncLastfm = val ?? false),
                    controlAffinity: ListTileControlAffinity.leading,
                    dense: true,
                    activeColor: AppTheme.spotifyGreen,
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 16),

          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton.icon(
              onPressed: _isLoading ? null : _startDumpMigration,
              icon: const Icon(CupertinoIcons.play_arrow_solid, size: 18),
              label: const Text('Start Full Data Migration', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.spotifyGreen,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSummaryMetric({
    required IconData icon,
    required Color color,
    required String title,
    required int count,
    required String caption,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _isDark ? AppTheme.darkDivider : AppTheme.lightDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(title, style: TextStyle(fontSize: 12, color: _isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            count.toString(),
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          Text(
            caption,
            style: TextStyle(fontSize: 10, color: _isDark ? Colors.grey.shade500 : Colors.grey.shade500),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 2b. Source Card Helpers (per detected dump part)
  // ===========================================================================

  Widget _buildKindBadge(String kind) {
    String label;
    Color color;
    switch (kind) {
      case 'account_data':
        label = 'Account Data';
        color = AppTheme.spotifyGreen;
        break;
      case 'streaming_history':
        label = 'Streaming History';
        color = Colors.orangeAccent;
        break;
      case 'mixed':
        label = 'Mixed';
        color = Colors.purpleAccent;
        break;
      default:
        label = 'Unknown';
        color = _isDark ? Colors.grey.shade400 : Colors.grey.shade600;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        label,
        style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color),
      ),
    );
  }

  Widget _buildSourceCount(String label, dynamic count) {
    return Column(
      children: [
        Text('$count', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(label, style: TextStyle(fontSize: 10, color: _isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
      ],
    );
  }

  Widget _buildSourceCard(Map<String, dynamic> source) {
    final kind = source['kind']?.toString() ?? 'unknown';
    final path = source['path']?.toString() ?? '';
    final summary = source['summary'] is Map ? Map<String, dynamic>.from(source['summary']) : <String, dynamic>{};

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _isDark ? AppTheme.darkDivider : AppTheme.lightDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _buildKindBadge(kind),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  path,
                  style: TextStyle(
                    fontSize: 11,
                    fontFamily: 'monospace',
                    color: _isDark ? Colors.grey.shade500 : Colors.grey.shade600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(child: _buildSourceCount('Playlists', summary['playlistsCount'] ?? 0)),
              Expanded(child: _buildSourceCount('Tracks', summary['libraryTracksCount'] ?? 0)),
              Expanded(child: _buildSourceCount('Albums', summary['libraryAlbumsCount'] ?? 0)),
              Expanded(child: _buildSourceCount('Scrobbles', summary['scrobblesCount'] ?? 0)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSourceStatusRow(Map<String, dynamic> source) {
    final migrated = source['migratedAt'] != null && (source['migratedAt']?.toString() ?? '').isNotEmpty;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _isDark ? AppTheme.darkDivider : AppTheme.lightDivider),
      ),
      child: Row(
        children: [
          _buildKindBadge(source['kind']?.toString() ?? 'unknown'),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              source['path']?.toString() ?? '',
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'monospace',
                color: _isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            migrated ? 'migrated' : 'not migrated',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: migrated ? AppTheme.spotifyGreen : Colors.orangeAccent,
            ),
          ),
        ],
      ),
    );
  }

  // ===========================================================================
  // 3. Shared Live Progress Dashboard
  // ===========================================================================

  Widget _buildProgressDashboard() {
    final status = _migrationStatus ?? {};
    final stateStr = status['status']?.toString() ?? 'running';
    final stage = status['currentStage']?.toString() ?? 'idle';
    final total = status['totalTracks'] is int ? status['totalTracks'] as int : 0;
    final processed = status['processedTracks'] is int ? status['processedTracks'] as int : 0;
    final stats = status['stats'] is Map ? Map<String, dynamic>.from(status['stats']) : {};
    final successCount = stats['success'] ?? 0;
    final skippedCount = stats['skipped'] ?? 0;
    final failedCount = stats['failed'] ?? 0;
    final currentTrack = status['currentTrack'] is Map ? Map<String, dynamic>.from(status['currentTrack']) : null;
    final logs = (status['recentLogs'] as List?)?.map((l) => l.toString()).toList() ?? [];
    final playlists = (status['createdPlaylists'] as List?)?.map((p) => p.toString()).toList() ?? [];
    final sources = (status['sources'] as List?)
            ?.whereType<Map>()
            .map((s) => Map<String, dynamic>.from(s))
            .toList() ??
        [];

    final progressVal = total > 0 ? (processed / total).clamp(0.0, 1.0) : 0.0;
    final isDone = stateStr == 'completed';
    final isFailed = stateStr == 'failed';
    final isCancelled = stateStr == 'cancelled';

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Status Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: _isDark ? AppTheme.darkSurface : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isDone
                  ? AppTheme.spotifyGreen.withOpacity(0.5)
                  : (isFailed ? Colors.redAccent.withOpacity(0.5) : (_isDark ? AppTheme.darkDivider : AppTheme.lightDivider)),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      if (!isDone && !isFailed && !isCancelled)
                        const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.spotifyGreen),
                        )
                      else if (isDone)
                        const Icon(CupertinoIcons.checkmark_seal_fill, color: AppTheme.spotifyGreen, size: 20)
                      else
                        const Icon(CupertinoIcons.exclamationmark_circle_fill, color: Colors.redAccent, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        _stageTitle(stage, stateStr),
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ],
                  ),
                  Text(
                    '${(progressVal * 100).toInt()}%',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppTheme.spotifyGreen),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  value: progressVal,
                  minHeight: 8,
                  backgroundColor: _isDark ? Colors.grey.shade800 : Colors.grey.shade300,
                  valueColor: AlwaysStoppedAnimation<Color>(
                    isDone ? AppTheme.spotifyGreen : (isFailed ? Colors.redAccent : AppTheme.spotifyGreen),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$processed of $total track operations completed',
                style: TextStyle(fontSize: 12, color: _isDark ? Colors.grey.shade400 : Colors.grey.shade600),
              ),
            ],
          ),
        ),

        const SizedBox(height: 12),

        // Live Track Banner
        if (currentTrack != null && !isDone)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: _isDark ? const Color(0xFF222222) : Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppTheme.spotifyGreen.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(CupertinoIcons.music_note, color: AppTheme.spotifyGreen, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        currentTrack['title'] ?? 'Processing track...',
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        '${currentTrack['artist'] ?? ''} • ${currentTrack['status'] ?? ''}',
                        style: TextStyle(fontSize: 11, color: _isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        const SizedBox(height: 12),

        // Stat Chips
        Row(
          children: [
            Expanded(
              child: _buildMetricChip(
                label: 'Imported',
                count: successCount,
                color: AppTheme.spotifyGreen,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricChip(
                label: 'In Library',
                count: skippedCount,
                color: Colors.blueAccent,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildMetricChip(
                label: 'Failed',
                count: failedCount,
                color: Colors.redAccent,
              ),
            ),
          ],
        ),

        if (playlists.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('Reconstructed Playlists (${playlists.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: playlists.map((p) => Chip(label: Text(p, style: const TextStyle(fontSize: 11)))).toList(),
          ),
        ],

        if (sources.isNotEmpty) ...[
          const SizedBox(height: 14),
          Text('Sources (${sources.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          const SizedBox(height: 6),
          for (final s in sources) _buildSourceStatusRow(s),
        ],

        const SizedBox(height: 16),

        // Live Log Terminal
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Live Logs', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
            TextButton.icon(
              icon: const Icon(CupertinoIcons.doc_on_doc, size: 14),
              label: const Text('Copy Logs', style: TextStyle(fontSize: 11)),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: logs.join('\n')));
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Logs copied to clipboard')));
              },
            ),
          ],
        ),
        Container(
          height: 220,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.black,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _isDark ? Colors.grey.shade800 : Colors.grey.shade300),
          ),
          child: ListView.builder(
            controller: _logScrollController,
            itemCount: logs.length,
            itemBuilder: (context, idx) {
              final line = logs[idx];
              Color textColor = Colors.grey.shade300;
              if (line.contains('Error') || line.contains('Failed')) {
                textColor = Colors.redAccent;
              } else if (line.contains('Success') || line.contains('Starred') || line.contains('finished')) {
                textColor = AppTheme.spotifyGreen;
              }
              return Text(
                line,
                style: TextStyle(fontFamily: 'monospace', fontSize: 11, color: textColor, height: 1.3),
              );
            },
          ),
        ),

        const SizedBox(height: 16),

        if (!isDone && !isFailed && !isCancelled)
          OutlinedButton.icon(
            onPressed: _cancelMigration,
            icon: const Icon(CupertinoIcons.stop_fill, color: Colors.redAccent, size: 16),
            label: const Text('Cancel Migration', style: TextStyle(color: Colors.redAccent)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: Colors.redAccent),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          )
        else
          ElevatedButton.icon(
            onPressed: () {
              setState(() {
                _currentStep = 0;
              });
            },
            icon: const Icon(CupertinoIcons.arrow_left, size: 16),
            label: const Text('Back to Setup'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.spotifyGreen,
              foregroundColor: Colors.black,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
      ],
    );
  }

  Widget _buildMetricChip({required String label, required dynamic count, required Color color}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
      decoration: BoxDecoration(
        color: _isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _isDark ? AppTheme.darkDivider : AppTheme.lightDivider),
      ),
      child: Column(
        children: [
          Text('$count', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 10, color: _isDark ? Colors.grey.shade400 : Colors.grey.shade600)),
        ],
      ),
    );
  }

  String _stageTitle(String stage, String state) {
    if (state == 'completed') return 'Migration Completed';
    if (state == 'failed') return 'Migration Failed';
    if (state == 'cancelled') return 'Migration Cancelled';

    switch (stage) {
      case 'fetching_metadata':
        return 'Extracting & Parsing Metadata...';
      case 'migrating_scrobbles':
        return 'Ingesting Scrobble Lake...';
      case 'migrating_liked_songs':
        return 'Importing Liked Songs...';
      case 'migrating_playlists':
        return 'Rebuilding Playlists...';
      default:
        return 'Migrating Spotify Library...';
    }
  }
}
