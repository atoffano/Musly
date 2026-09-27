import 'dart:async';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cached_network_image/cached_network_image.dart';

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
  static const String _prefClientIdKey = 'spotify_migration_client_id';

  final MuslyBackendService _backend = MuslyBackendService();
  final TextEditingController _clientIdController = TextEditingController();
  final TextEditingController _manualCodeController = TextEditingController();
  final TextEditingController _playlistSearchController = TextEditingController();

  int _currentStep = 0; // 0: Auth, 1: Selection, 2: Progress
  bool _isLoading = false;
  String? _errorMessage;

  // PKCE state
  String? _codeVerifier;
  String? _expectedState;
  Timer? _callbackPollTimer;
  bool _isWaitingForAuth = false;

  // Spotify User Profile & Summary
  Map<String, dynamic>? _userProfile;
  int _likedSongsCount = 0;
  List<Map<String, dynamic>> _playlists = [];
  List<Map<String, dynamic>> _albums = [];

  // Selection state (Default: import all available info)
  bool _importAll = true;
  bool _importLikedSongs = true;
  final Set<String> _selectedPlaylistIds = {};
  final Set<String> _selectedAlbumIds = {};
  String _playlistSearchQuery = '';

  // Migration status
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
    _loadInitialState();
  }

  @override
  void dispose() {
    _callbackPollTimer?.cancel();
    _statusPollTimer?.cancel();
    _clientIdController.dispose();
    _manualCodeController.dispose();
    _playlistSearchController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialState() async {
    final prefs = await SharedPreferences.getInstance();
    final savedClientId = prefs.getString(_prefClientIdKey) ?? '';
    if (savedClientId.isNotEmpty) {
      _clientIdController.text = savedClientId;
    }

    final bridgeUrl = _getEffectiveBridgeUrl();
    if (bridgeUrl.isEmpty) return;

    try {
      final config = await _backend.getSpotifyConfig(bridgeUrl);
      if (_clientIdController.text.isEmpty && config['clientId']?.isNotEmpty == true) {
        _clientIdController.text = config['clientId'];
      }

      // Check if migration is currently running
      final status = await _backend.getSpotifyMigrationStatus(bridgeUrl);
      if (status['status'] == 'running') {
        if (mounted) {
          setState(() {
            _currentStep = 2;
            _migrationStatus = status;
          });
          _startStatusPolling();
          return;
        }
      }

      final session = config['session'] as Map?;
      if (session != null && session['connected'] == true) {
        if (mounted) {
          setState(() {
            _userProfile = session['user'] as Map<String, dynamic>?;
          });
          await _fetchSpotifyLibrary(bridgeUrl);
        }
      }
    } catch (_) {}
  }

  // =========================================================================
  // PKCE Flow
  // =========================================================================

  Future<void> _startSpotifyAuth() async {
    final clientId = _clientIdController.text.trim();
    if (clientId.isEmpty) {
      setState(() => _errorMessage = 'Please enter your Spotify Client ID.');
      return;
    }

    final bridgeUrl = _getEffectiveBridgeUrl();
    if (bridgeUrl.isEmpty) {
      setState(() => _errorMessage = 'Music Pipeline bridge URL is unavailable.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _isWaitingForAuth = true;
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefClientIdKey, clientId);

    try {
      final redirectUri = '$bridgeUrl/api/spotify/callback';
      final initData = await _backend.initSpotifyPkce(
        bridgeUrl,
        clientId: clientId,
        redirectUri: redirectUri,
      );

      _codeVerifier = initData['codeVerifier']?.toString();
      _expectedState = initData['state']?.toString();
      final authUrl = initData['authUrl']?.toString() ?? '';

      if (authUrl.isNotEmpty) {
        final uri = Uri.parse(authUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw Exception('Could not launch Spotify authorization URL.');
        }
      }

      // Start automatic callback polling
      _startCallbackPolling(bridgeUrl, clientId, redirectUri);
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isWaitingForAuth = false;
          _errorMessage = 'Failed to initiate authorization: $e';
        });
      }
    }
  }

  void _startCallbackPolling(String bridgeUrl, String clientId, String redirectUri) {
    _callbackPollTimer?.cancel();
    _callbackPollTimer = Timer.periodic(const Duration(seconds: 2), (timer) async {
      try {
        final latest = await _backend.getLatestSpotifyCallback(bridgeUrl);
        final code = latest['code']?.toString() ?? '';
        final state = latest['state']?.toString() ?? '';

        if (code.isNotEmpty && (_expectedState == null || state == _expectedState)) {
          timer.cancel();
          await _finishTokenExchange(
            bridgeUrl: bridgeUrl,
            clientId: clientId,
            code: code,
            redirectUri: redirectUri,
          );
        }
      } catch (_) {}
    });
  }

  Future<void> _submitManualCode() async {
    final input = _manualCodeController.text.trim();
    if (input.isEmpty) return;

    String code = input;
    if (input.contains('code=')) {
      final uri = Uri.tryParse(input);
      if (uri != null) {
        code = uri.queryParameters['code'] ?? code;
      }
    }

    final bridgeUrl = _getEffectiveBridgeUrl();
    final clientId = _clientIdController.text.trim();
    final redirectUri = '$bridgeUrl/api/spotify/callback';

    await _finishTokenExchange(
      bridgeUrl: bridgeUrl,
      clientId: clientId,
      code: code,
      redirectUri: redirectUri,
    );
  }

  Future<void> _finishTokenExchange({
    required String bridgeUrl,
    required String clientId,
    required String code,
    required String redirectUri,
  }) async {
    _callbackPollTimer?.cancel();
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final tokenResult = await _backend.exchangeSpotifyPkce(
        bridgeUrl,
        clientId: clientId,
        code: code,
        codeVerifier: _codeVerifier ?? '',
        redirectUri: redirectUri,
      );

      if (mounted) {
        setState(() {
          _userProfile = tokenResult['user'] as Map<String, dynamic>?;
          _isWaitingForAuth = false;
        });
        await _fetchSpotifyLibrary(bridgeUrl);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isWaitingForAuth = false;
          _errorMessage = 'Authentication failed: $e';
        });
      }
    }
  }

  Future<void> _fetchSpotifyLibrary(String bridgeUrl) async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final summary = await _backend.getSpotifySummary(bridgeUrl);
      final playlists = await _backend.getSpotifyPlaylists(bridgeUrl);
      final albums = await _backend.getSpotifyAlbums(bridgeUrl);

      if (mounted) {
        setState(() {
          _likedSongsCount = (summary['likedSongsCount'] as num?)?.toInt() ?? 0;
          _playlists = playlists;
          _albums = albums;
          _isLoading = false;
          _currentStep = 1; // Transition to selection view

          // Default: select all
          _selectedPlaylistIds.clear();
          for (final p in _playlists) {
            final id = p['id']?.toString();
            if (id != null) _selectedPlaylistIds.add(id);
          }
          _selectedAlbumIds.clear();
          for (final a in _albums) {
            final id = a['id']?.toString();
            if (id != null) _selectedAlbumIds.add(id);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load library details: $e';
        });
      }
    }
  }

  // =========================================================================
  // Migration Execution & Monitoring
  // =========================================================================

  Future<void> _startMigration() async {
    final bridgeUrl = _getEffectiveBridgeUrl();
    if (bridgeUrl.isEmpty) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await _backend.startSpotifyMigration(
        bridgeUrl,
        importAll: _importAll,
        importLikedSongs: _importAll || _importLikedSongs,
        playlistIds: _importAll ? [] : _selectedPlaylistIds.toList(),
        albumIds: _importAll ? [] : _selectedAlbumIds.toList(),
      );

      if (mounted) {
        setState(() {
          _isLoading = false;
          _currentStep = 2; // Transition to live progress view
          _migrationStatus = result['job'] as Map<String, dynamic>?;
        });
        _startStatusPolling();
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to start migration: $e';
        });
      }
    }
  }

  void _startStatusPolling() {
    _statusPollTimer?.cancel();
    final bridgeUrl = _getEffectiveBridgeUrl();

    _statusPollTimer = Timer.periodic(const Duration(milliseconds: 1200), (timer) async {
      try {
        final status = await _backend.getSpotifyMigrationStatus(bridgeUrl);
        if (mounted) {
          setState(() {
            _migrationStatus = status;
          });
        }
        final runStatus = status['status']?.toString();
        if (runStatus == 'completed' || runStatus == 'cancelled' || runStatus == 'failed') {
          timer.cancel();
        }
      } catch (_) {}
    });
  }

  Future<void> _cancelMigration() async {
    final bridgeUrl = _getEffectiveBridgeUrl();
    if (bridgeUrl.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel Migration?'),
        content: const Text('Are you sure you want to stop the active Spotify migration? Any tracks already ingested will remain in your Navidrome library.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Continue Migration'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Stop Migration'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _backend.cancelSpotifyMigration(bridgeUrl);
      } catch (_) {}
    }
  }

  // =========================================================================
  // UI Builder
  // =========================================================================

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
        actions: [
          if (_currentStep == 1 && _userProfile != null)
            TextButton.icon(
              icon: const Icon(CupertinoIcons.arrow_counterclockwise, size: 16),
              label: const Text('Re-fetch'),
              onPressed: () => _fetchSpotifyLibrary(_getEffectiveBridgeUrl()),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildStepperHeader(),
            if (_errorMessage != null) _buildErrorBanner(_errorMessage!),
            Expanded(
              child: _isLoading && _currentStep != 2
                  ? const Center(child: CircularProgressIndicator(color: AppTheme.spotifyGreen))
                  : _buildCurrentStepView(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepperHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: _isDark ? AppTheme.darkSurface : Colors.white,
        border: Border(bottom: BorderSide(color: _isDark ? AppTheme.darkDivider : AppTheme.lightDivider, width: 0.5)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildStepIndicator(0, 'Connect', CupertinoIcons.person_crop_circle_badge_checkmark),
          _buildStepDivider(0),
          _buildStepIndicator(1, 'Select', CupertinoIcons.square_stack_3d_up),
          _buildStepDivider(1),
          _buildStepIndicator(2, 'Migrate', CupertinoIcons.arrow_2_circlepath_circle),
        ],
      ),
    );
  }

  Widget _buildStepIndicator(int stepIndex, String title, IconData icon) {
    final isActive = _currentStep == stepIndex;
    final isDone = _currentStep > stepIndex;
    final color = isActive
        ? AppTheme.spotifyGreen
        : isDone
            ? Colors.green
            : (_isDark ? AppTheme.darkSecondaryText : AppTheme.lightSecondaryText);

    return InkWell(
      onTap: isDone ? () => setState(() => _currentStep = stepIndex) : null,
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: isActive ? 0.2 : 0.1),
              shape: BoxShape.circle,
              border: Border.all(color: color, width: isActive ? 2 : 1),
            ),
            child: Icon(isDone ? Icons.check : icon, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: TextStyle(
              fontSize: 13,
              fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepDivider(int afterStep) {
    final isDone = _currentStep > afterStep;
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 12),
        color: isDone ? Colors.green : (_isDark ? AppTheme.darkDivider : AppTheme.lightDivider),
      ),
    );
  }

  Widget _buildErrorBanner(String message) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.exclamationmark_triangle_fill, color: Colors.red, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: const TextStyle(color: Colors.red, fontSize: 13))),
          IconButton(
            icon: const Icon(Icons.close, size: 16, color: Colors.red),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
            onPressed: () => setState(() => _errorMessage = null),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStepView() {
    switch (_currentStep) {
      case 0:
        return _buildAuthStep();
      case 1:
        return _buildSelectionStep();
      case 2:
        return _buildProgressStep();
      default:
        return _buildAuthStep();
    }
  }

  // =========================================================================
  // STEP 0: Authentication
  // =========================================================================

  Widget _buildAuthStep() {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildHeroBanner(),
        const SizedBox(height: 24),
        if (_userProfile != null) ...[
          _buildConnectedUserCard(),
          const SizedBox(height: 24),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.spotifyGreen,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(CupertinoIcons.arrow_right, size: 18),
            label: const Text('Continue to Selection', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            onPressed: () => _fetchSpotifyLibrary(_getEffectiveBridgeUrl()),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(CupertinoIcons.arrow_swap, size: 16),
            label: const Text('Switch Spotify Account'),
            onPressed: () => setState(() => _userProfile = null),
          ),
        ] else ...[
          _buildClientIdInputCard(),
          const SizedBox(height: 20),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.spotifyGreen,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(CupertinoIcons.link, size: 20),
            label: const Text('Login with Spotify', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            onPressed: _startSpotifyAuth,
          ),
          if (_isWaitingForAuth) ...[
            const SizedBox(height: 24),
            _buildWaitingForAuthIndicator(),
          ],
          const SizedBox(height: 24),
          _buildManualCodeInputAccordion(),
        ],
      ],
    );
  }

  Widget _buildHeroBanner() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppTheme.spotifyGreen.withValues(alpha: 0.15),
            _isDark ? AppTheme.darkSurface : Colors.white,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.spotifyGreen.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: const BoxDecoration(
                  color: AppTheme.spotifyGreen,
                  shape: BoxShape.circle,
                ),
                child: const Icon(CupertinoIcons.music_albums, color: Colors.black, size: 24),
              ),
              const SizedBox(width: 12),
              const Icon(CupertinoIcons.arrow_right, size: 18, color: AppTheme.spotifyGreen),
              const SizedBox(width: 12),
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(CupertinoIcons.cloud_download, color: Colors.white, size: 24),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text(
            'Spotify to Navidrome Migration',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          Text(
            'Authenticate with Spotify to import your playlists, liked albums, and favorite songs directly into your personal Navidrome streaming library.',
            style: TextStyle(
              fontSize: 13,
              color: _isDark ? AppTheme.darkSecondaryText : AppTheme.lightSecondaryText,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientIdInputCard() {
    final bridgeUrl = _getEffectiveBridgeUrl();
    final redirectUri = '$bridgeUrl/api/spotify/callback';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _isDark ? AppTheme.darkDivider : AppTheme.lightDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Spotify Client ID', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            'From your Spotify Developer Dashboard. Uses PKCE Authorization Code flow (no Client Secret needed).',
            style: TextStyle(
              fontSize: 12,
              color: _isDark ? AppTheme.darkSecondaryText : AppTheme.lightSecondaryText,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _clientIdController,
            decoration: InputDecoration(
              hintText: 'Enter 32-character Client ID',
              filled: true,
              fillColor: _isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
              prefixIcon: const Icon(CupertinoIcons.lock_shield, size: 18),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Setup Instructions & Redirect URI', style: TextStyle(fontSize: 13, color: AppTheme.spotifyGreen)),
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 4, bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('1. Go to developer.spotify.com/dashboard and create a free app.', style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 4),
                      const Text('2. In your App Settings, add this exact Redirect URI:', style: TextStyle(fontSize: 12)),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: _isDark ? Colors.black : Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            Expanded(child: SelectableText(redirectUri, style: const TextStyle(fontFamily: 'monospace', fontSize: 11))),
                            IconButton(
                              icon: const Icon(CupertinoIcons.doc_on_doc, size: 14),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: () {
                                Clipboard.setData(ClipboardData(text: redirectUri));
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Redirect URI copied to clipboard!')));
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      const Text('3. Copy your Client ID and paste it above.', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConnectedUserCard() {
    final name = _userProfile?['displayName'] ?? 'Spotify User';
    final email = _userProfile?['email'] ?? '';
    final avatar = _userProfile?['avatarUrl'] as String?;
    final followers = _userProfile?['followers'] ?? 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.spotifyGreen.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: AppTheme.spotifyGreen.withValues(alpha: 0.2),
            backgroundImage: avatar != null ? CachedNetworkImageProvider(avatar) : null,
            child: avatar == null ? const Icon(CupertinoIcons.person, color: AppTheme.spotifyGreen, size: 28) : null,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(child: Text(name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(color: AppTheme.spotifyGreen.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(6)),
                      child: const Text('Connected', style: TextStyle(color: AppTheme.spotifyGreen, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
                if (email.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(email, style: TextStyle(fontSize: 13, color: _isDark ? AppTheme.darkSecondaryText : AppTheme.lightSecondaryText)),
                ],
                const SizedBox(height: 2),
                Text('$followers followers', style: TextStyle(fontSize: 12, color: _isDark ? AppTheme.darkSecondaryText : AppTheme.lightSecondaryText)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWaitingForAuthIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.spotifyGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.spotifyGreen.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          const SizedBox(
            height: 24,
            width: 24,
            child: CircularProgressIndicator(strokeWidth: 2.5, color: AppTheme.spotifyGreen),
          ),
          const SizedBox(height: 12),
          const Text('Waiting for authorization in your browser...', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text(
            'Grant permissions on Spotify. Musly will automatically detect the authorization and advance.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12, color: _isDark ? AppTheme.darkSecondaryText : AppTheme.lightSecondaryText),
          ),
        ],
      ),
    );
  }

  Widget _buildManualCodeInputAccordion() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _isDark ? AppTheme.darkDivider : AppTheme.lightDivider),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Having trouble with browser redirect?', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(
            'You can paste the redirected URL or authorization code directly here.',
            style: TextStyle(fontSize: 12, color: _isDark ? AppTheme.darkSecondaryText : AppTheme.lightSecondaryText),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _manualCodeController,
                  decoration: InputDecoration(
                    hintText: 'Paste code or redirect URL',
                    filled: true,
                    fillColor: _isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: AppTheme.spotifyGreen, foregroundColor: Colors.black),
                onPressed: _submitManualCode,
                child: const Text('Verify'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // STEP 1: Library Selection
  // =========================================================================

  Widget _buildSelectionStep() {
    final filteredPlaylists = _playlistSearchQuery.isEmpty
        ? _playlists
        : _playlists.where((p) {
            final name = (p['name'] ?? '').toString().toLowerCase();
            return name.contains(_playlistSearchQuery.toLowerCase());
          }).toList();

    return Column(
      children: [
        _buildMasterImportToggle(),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
            children: [
              _buildLikedSongsSection(),
              const SizedBox(height: 20),
              _buildPlaylistsSection(filteredPlaylists),
              if (_albums.isNotEmpty) ...[
                const SizedBox(height: 20),
                _buildAlbumsSection(),
              ],
            ],
          ),
        ),
        _buildBottomActionBar(),
      ],
    );
  }

  Widget _buildMasterImportToggle() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.spotifyGreen.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.spotifyGreen.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(CupertinoIcons.sparkles, color: AppTheme.spotifyGreen, size: 22),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Import all available info', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                Text('Imports Liked Songs, all Playlists, and saved Albums', style: TextStyle(fontSize: 12, color: AppTheme.spotifyGreen)),
              ],
            ),
          ),
          Switch(
            value: _importAll,
            activeColor: AppTheme.spotifyGreen,
            onChanged: (val) {
              setState(() {
                _importAll = val;
                if (val) {
                  _importLikedSongs = true;
                  _selectedPlaylistIds.addAll(_playlists.map((p) => p['id']?.toString() ?? ''));
                  _selectedAlbumIds.addAll(_albums.map((a) => a['id']?.toString() ?? ''));
                }
              });
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLikedSongsSection() {
    return Container(
      decoration: BoxDecoration(
        color: _isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: CheckboxListTile(
        activeColor: AppTheme.spotifyGreen,
        checkColor: Colors.black,
        value: _importAll || _importLikedSongs,
        onChanged: _importAll ? null : (val) => setState(() => _importLikedSongs = val ?? true),
        secondary: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [Color(0xFF450AF5), Color(0xFFC4EFD9)]),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(CupertinoIcons.heart_fill, color: Colors.white, size: 20),
        ),
        title: const Text('Liked Songs', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
        subtitle: Text('$_likedSongsCount songs in Spotify library', style: TextStyle(fontSize: 13, color: _isDark ? AppTheme.darkSecondaryText : AppTheme.lightSecondaryText)),
      ),
    );
  }

  Widget _buildPlaylistsSection(List<Map<String, dynamic>> filteredPlaylists) {
    return Container(
      decoration: BoxDecoration(
        color: _isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text('Playlists', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('${_selectedPlaylistIds.length}/${_playlists.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                if (!_importAll) ...[
                  Row(
                    children: [
                      TextButton(
                        child: const Text('Select All', style: TextStyle(fontSize: 12, color: AppTheme.spotifyGreen)),
                        onPressed: () => setState(() => _selectedPlaylistIds.addAll(_playlists.map((p) => p['id']?.toString() ?? ''))),
                      ),
                      TextButton(
                        child: const Text('Clear', style: TextStyle(fontSize: 12, color: Colors.red)),
                        onPressed: () => setState(() => _selectedPlaylistIds.clear()),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: TextField(
              controller: _playlistSearchController,
              decoration: InputDecoration(
                hintText: 'Search playlists...',
                prefixIcon: const Icon(CupertinoIcons.search, size: 16),
                filled: true,
                fillColor: _isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
              ),
              onChanged: (val) => setState(() => _playlistSearchQuery = val),
            ),
          ),
          const Divider(height: 1),
          if (filteredPlaylists.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Center(child: Text('No playlists found')))
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: filteredPlaylists.length,
              separatorBuilder: (_, __) => const Divider(height: 1, indent: 64),
              itemBuilder: (context, index) {
                final playlist = filteredPlaylists[index];
                final id = playlist['id']?.toString() ?? '';
                final name = playlist['name']?.toString() ?? 'Untitled';
                final totalTracks = playlist['totalTracks'] ?? 0;
                final cover = playlist['coverArtUrl'] as String?;
                final owner = playlist['owner']?.toString() ?? '';
                final isSelected = _importAll || _selectedPlaylistIds.contains(id);

                return CheckboxListTile(
                  activeColor: AppTheme.spotifyGreen,
                  checkColor: Colors.black,
                  value: isSelected,
                  onChanged: _importAll
                      ? null
                      : (val) {
                          setState(() {
                            if (val == true) {
                              _selectedPlaylistIds.add(id);
                            } else {
                              _selectedPlaylistIds.remove(id);
                            }
                          });
                        },
                  secondary: ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: cover != null
                        ? CachedNetworkImage(
                            imageUrl: cover,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _buildPlaceholderArt(),
                          )
                        : _buildPlaceholderArt(),
                  ),
                  title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
                  subtitle: Text('$totalTracks songs • by $owner', style: TextStyle(fontSize: 12, color: _isDark ? AppTheme.darkSecondaryText : AppTheme.lightSecondaryText)),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildAlbumsSection() {
    return Container(
      decoration: BoxDecoration(
        color: _isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Text('Saved Albums', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: _isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('${_selectedAlbumIds.length}/${_albums.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
                if (!_importAll) ...[
                  Row(
                    children: [
                      TextButton(
                        child: const Text('Select All', style: TextStyle(fontSize: 12, color: AppTheme.spotifyGreen)),
                        onPressed: () => setState(() => _selectedAlbumIds.addAll(_albums.map((a) => a['id']?.toString() ?? ''))),
                      ),
                      TextButton(
                        child: const Text('Clear', style: TextStyle(fontSize: 12, color: Colors.red)),
                        onPressed: () => setState(() => _selectedAlbumIds.clear()),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          const Divider(height: 1),
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: _albums.length,
            separatorBuilder: (_, __) => const Divider(height: 1, indent: 64),
            itemBuilder: (context, index) {
              final album = _albums[index];
              final id = album['id']?.toString() ?? '';
              final name = album['name']?.toString() ?? 'Untitled';
              final artist = album['artist']?.toString() ?? 'Unknown';
              final tracksCount = album['totalTracks'] ?? 0;
              final cover = album['coverArtUrl'] as String?;
              final isSelected = _importAll || _selectedAlbumIds.contains(id);

              return CheckboxListTile(
                activeColor: AppTheme.spotifyGreen,
                checkColor: Colors.black,
                value: isSelected,
                onChanged: _importAll
                    ? null
                    : (val) {
                        setState(() {
                          if (val == true) {
                            _selectedAlbumIds.add(id);
                          } else {
                            _selectedAlbumIds.remove(id);
                          }
                        });
                      },
                secondary: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: cover != null
                      ? CachedNetworkImage(imageUrl: cover, width: 44, height: 44, fit: BoxFit.cover, errorWidget: (_, __, ___) => _buildPlaceholderArt())
                      : _buildPlaceholderArt(),
                ),
                title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
                subtitle: Text('$artist • $tracksCount songs', style: TextStyle(fontSize: 12, color: _isDark ? AppTheme.darkSecondaryText : AppTheme.lightSecondaryText)),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderArt() {
    return Container(
      width: 44,
      height: 44,
      color: Colors.grey.withValues(alpha: 0.2),
      child: const Icon(CupertinoIcons.music_note, size: 20, color: Colors.grey),
    );
  }

  Widget _buildBottomActionBar() {
    final selectedPlaylistsCount = _importAll ? _playlists.length : _selectedPlaylistIds.length;
    final selectedAlbumsCount = _importAll ? _albums.length : _selectedAlbumIds.length;
    final isLikedSongsSelected = _importAll || _importLikedSongs;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: _isDark ? AppTheme.darkSurface : Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, -4))],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _importAll
                      ? 'Importing Everything'
                      : '$selectedPlaylistsCount playlists, $selectedAlbumsCount albums',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                Text(
                  isLikedSongsSelected ? 'Including Liked Songs' : 'Excluding Liked Songs',
                  style: TextStyle(fontSize: 12, color: _isDark ? AppTheme.darkSecondaryText : AppTheme.lightSecondaryText),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.spotifyGreen,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(CupertinoIcons.arrow_down_circle_fill, size: 18),
            label: const Text('Start Ingestion', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            onPressed: _startMigration,
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // STEP 2: Progress & Monitoring
  // =========================================================================

  Widget _buildProgressStep() {
    final status = _migrationStatus?['status']?.toString() ?? 'idle';
    final stage = _migrationStatus?['currentStage']?.toString() ?? 'idle';
    final total = (_migrationStatus?['totalTracks'] as num?)?.toInt() ?? 0;
    final processed = (_migrationStatus?['processedTracks'] as num?)?.toInt() ?? 0;
    final stats = _migrationStatus?['stats'] as Map? ?? {};
    final success = (stats['success'] as num?)?.toInt() ?? 0;
    final skipped = (stats['skipped'] as num?)?.toInt() ?? 0;
    final failed = (stats['failed'] as num?)?.toInt() ?? 0;
    final currentTrack = _migrationStatus?['currentTrack'] as Map?;
    final createdPlaylists = (_migrationStatus?['createdPlaylists'] as List?)?.map((e) => e.toString()).toList() ?? [];
    final logs = (_migrationStatus?['recentLogs'] as List?)?.map((e) => e.toString()).toList() ?? [];

    final progressRatio = total > 0 ? (processed / total).clamp(0.0, 1.0) : 0.0;
    final isRunning = status == 'running';
    final isCompleted = status == 'completed';

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        _buildStatusHeader(status, stage),
        const SizedBox(height: 20),
        _buildProgressBarCard(progressRatio, processed, total),
        const SizedBox(height: 16),
        _buildMetricsGrid(success, skipped, failed),
        const SizedBox(height: 16),
        if (currentTrack != null && isRunning) ...[
          _buildCurrentTrackCard(currentTrack),
          const SizedBox(height: 16),
        ],
        if (createdPlaylists.isNotEmpty) ...[
          _buildCreatedPlaylistsCard(createdPlaylists),
          const SizedBox(height: 16),
        ],
        _buildLogsCard(logs),
        const SizedBox(height: 24),
        if (isRunning)
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red,
              side: const BorderSide(color: Colors.red),
              minimumSize: const Size(double.infinity, 48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(CupertinoIcons.stop_circle, size: 20),
            label: const Text('Cancel Migration'),
            onPressed: _cancelMigration,
          )
        else if (isCompleted)
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.spotifyGreen,
              foregroundColor: Colors.black,
              minimumSize: const Size(double.infinity, 50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            icon: const Icon(CupertinoIcons.check_mark_circled_solid, size: 20),
            label: const Text('Done • Return to Settings', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            onPressed: () => Navigator.of(context).pop(),
          ),
      ],
    );
  }

  Widget _buildStatusHeader(String status, String stage) {
    Color badgeColor;
    String badgeText;
    switch (status) {
      case 'running':
        badgeColor = AppTheme.spotifyGreen;
        badgeText = 'IN PROGRESS';
        break;
      case 'completed':
        badgeColor = Colors.green;
        badgeText = 'COMPLETED';
        break;
      case 'cancelled':
        badgeColor = Colors.orange;
        badgeText = 'CANCELLED';
        break;
      case 'failed':
        badgeColor = Colors.red;
        badgeText = 'FAILED';
        break;
      default:
        badgeColor = Colors.grey;
        badgeText = status.toUpperCase();
    }

    String stageLabel;
    switch (stage) {
      case 'fetching_metadata':
        stageLabel = 'Fetching catalog details from Spotify...';
        break;
      case 'migrating_liked_songs':
        stageLabel = 'Migrating Liked Songs to Navidrome...';
        break;
      case 'migrating_playlists':
        stageLabel = 'Building and synchronizing Playlists...';
        break;
      case 'migrating_albums':
        stageLabel = 'Ingesting Saved Albums...';
        break;
      case 'done':
        stageLabel = 'All tracks processed and playlists created!';
        break;
      default:
        stageLabel = stage;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Pipeline Status', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(color: badgeColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(8)),
                child: Text(badgeText, style: TextStyle(color: badgeColor, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(stageLabel, style: TextStyle(fontSize: 14, color: _isDark ? Colors.white70 : Colors.black87)),
        ],
      ),
    );
  }

  Widget _buildProgressBarCard(double ratio, int processed, int total) {
    final percent = (ratio * 100).toInt();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('$percent% Complete', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Text('$processed of $total tracks', style: TextStyle(fontSize: 14, color: _isDark ? AppTheme.darkSecondaryText : AppTheme.lightSecondaryText)),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: total > 0 ? ratio : null,
              minHeight: 10,
              backgroundColor: _isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
              color: AppTheme.spotifyGreen,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricsGrid(int success, int skipped, int failed) {
    return Row(
      children: [
        Expanded(child: _buildMetricTile('Imported', '$success', Colors.green, CupertinoIcons.arrow_down_circle)),
        const SizedBox(width: 8),
        Expanded(child: _buildMetricTile('In Library', '$skipped', const Color(0xFF007AFF), CupertinoIcons.checkmark_circle)),
        const SizedBox(width: 8),
        Expanded(child: _buildMetricTile('Failed', '$failed', Colors.orange, CupertinoIcons.exclamationmark_circle)),
      ],
    );
  }

  Widget _buildMetricTile(String label, String value, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
      decoration: BoxDecoration(
        color: _isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 6),
          Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
          const SizedBox(height: 2),
          Text(label, style: TextStyle(fontSize: 12, color: _isDark ? AppTheme.darkSecondaryText : AppTheme.lightSecondaryText)),
        ],
      ),
    );
  }

  Widget _buildCurrentTrackCard(Map track) {
    final title = track['title']?.toString() ?? '';
    final artist = track['artist']?.toString() ?? '';
    final status = track['status']?.toString() ?? '';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.spotifyGreen.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.spotifyGreen.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.spotifyGreen),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                Text(artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: 12, color: _isDark ? AppTheme.darkSecondaryText : AppTheme.lightSecondaryText)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(color: _isDark ? Colors.black : Colors.white, borderRadius: BorderRadius.circular(6)),
            child: Text(status.replaceAll('_', ' '), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.spotifyGreen)),
          ),
        ],
      ),
    );
  }

  Widget _buildCreatedPlaylistsCard(List<String> playlists) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Created Navidrome Playlists', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: playlists.map((name) {
              return Chip(
                avatar: const Icon(CupertinoIcons.music_albums, size: 14, color: AppTheme.spotifyGreen),
                label: Text(name, style: const TextStyle(fontSize: 12)),
                backgroundColor: _isDark ? AppTheme.darkBackground : AppTheme.lightBackground,
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildLogsCard(List<String> logs) {
    return Container(
      decoration: BoxDecoration(
        color: _isDark ? AppTheme.darkSurface : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          title: const Text('Activity Logs', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          children: [
            Container(
              height: 200,
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              decoration: BoxDecoration(
                color: _isDark ? Colors.black : Colors.grey.shade900,
                borderRadius: BorderRadius.circular(8),
              ),
              child: ListView.builder(
                reverse: true,
                itemCount: logs.length,
                itemBuilder: (context, idx) {
                  final line = logs[logs.length - 1 - idx];
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(line, style: const TextStyle(fontFamily: 'monospace', fontSize: 11, color: Color(0xFFC0CAF5))),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
