import 'dart:ui';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/song.dart';
import '../providers/library_provider.dart';
import '../providers/player_provider.dart';
import '../theme/app_theme.dart';
import '../widgets/album_artwork.dart';
import '../widgets/song_tile.dart';

class BridgeArtistScreen extends StatefulWidget {
  final String artistName;
  final String? browseId;
  final String? heroCoverArt;

  const BridgeArtistScreen({
    super.key,
    required this.artistName,
    this.browseId,
    this.heroCoverArt,
  });

  @override
  State<BridgeArtistScreen> createState() => _BridgeArtistScreenState();
}

class _BridgeArtistScreenState extends State<BridgeArtistScreen> {
  bool _isLoading = true;
  String? _error;
  List<Song> _topSongs = [];
  String? _heroCoverArt;

  @override
  void initState() {
    super.initState();
    _heroCoverArt = widget.heroCoverArt;
    _loadArtistData();
  }

  Future<void> _loadArtistData() async {
    final library = context.read<LibraryProvider>();
    final bridgeUrl = _bridgeBaseUrl(library);

    if (bridgeUrl == null) {
      setState(() {
        _isLoading = false;
        _error = 'Bridge server unavailable';
      });
      return;
    }

    try {
      if (widget.browseId != null && widget.browseId!.isNotEmpty) {
        final top = await library
            .muslyBackendService
            .artistTopSongs(bridgeUrl, widget.browseId!);
        _topSongs = top.songs;

        if (_topSongs.isEmpty) {
          final discography = await library
              .muslyBackendService
              .artistDiscography(bridgeUrl, widget.browseId!);
          _topSongs = discography.songs;
        }
      } else {
        final search = await library.muslyBackendService.searchSongs(
          bridgeUrl,
          widget.artistName,
        );
        _topSongs = search.songs
            .where((song) =>
                (song.artist ?? '').toLowerCase().contains(widget.artistName.toLowerCase()))
            .toList();
      }

      if (_heroCoverArt == null || _heroCoverArt!.isEmpty) {
        _heroCoverArt = _topSongs
            .map((song) => song.coverArt)
            .firstWhere((cover) => cover != null && cover.isNotEmpty, orElse: () => null);
      }

      if (!mounted) return;
      setState(() => _isLoading = false);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  String? _bridgeBaseUrl(LibraryProvider library) {
    final config = library.subsonicService.config;
    if (config == null || config.serverUrl.isEmpty) {
      return null;
    }
    final uri = Uri.tryParse(config.serverUrl);
    if (uri == null || uri.host.isEmpty) {
      return null;
    }
    return '${uri.scheme}://${uri.host}:8788';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(widget.artistName)),
        body: Center(
          child: Text(
            'Failed loading artist: $_error',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            pinned: true,
            expandedHeight: 230,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(widget.artistName),
              titlePadding: const EdgeInsetsDirectional.only(
                start: 16,
                end: 16,
                bottom: 102,
              ),
              background: Stack(
                fit: StackFit.expand,
                children: [
                  if (_heroCoverArt != null)
                    ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: AlbumArtwork(
                        coverArt: _heroCoverArt,
                        size: 600,
                        preserveAspectRatio: true,
                        shadow: const BoxShadow(color: Colors.transparent),
                      ),
                    )
                  else
                    Container(color: AppTheme.appleMusicRed.withValues(alpha: 0.15)),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.05),
                          Colors.black.withValues(alpha: 0.55),
                        ],
                      ),
                    ),
                  ),
                  Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          ClipOval(
                            child: AlbumArtwork(
                              coverArt: _heroCoverArt,
                              size: 72,
                              borderRadius: 36,
                              shadow: const BoxShadow(color: Colors.transparent),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              '${_topSongs.length} tracks found',
                              style: const TextStyle(color: Colors.white70),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              IconButton(
                icon: const Icon(CupertinoIcons.play_fill),
                onPressed: _topSongs.isEmpty
                    ? null
                    : () {
                        final player = context.read<PlayerProvider>();
                        player.playSong(
                          _topSongs.first,
                          playlist: _topSongs,
                          startIndex: 0,
                        );
                      },
              ),
            ],
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                'Top Songs',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
          ),
          if (_topSongs.isEmpty)
            const SliverFillRemaining(
              child: Center(child: Text('No songs available for this artist.')),
            )
          else
            SliverList.builder(
              itemCount: _topSongs.length,
              itemBuilder: (context, index) {
                final song = _topSongs[index];
                return SongTile(
                  song: song,
                  playlist: _topSongs,
                  index: index,
                  showArtist: true,
                  showAlbum: true,
                );
              },
            ),
        ],
      ),
    );
  }
}
