import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/library_provider.dart';
import '../models/models.dart';
import '../widgets/widgets.dart';
import '../theme/app_theme.dart';
import 'album_screen.dart';

class AllAlbumsScreen extends StatefulWidget {
  const AllAlbumsScreen({super.key});

  @override
  State<AllAlbumsScreen> createState() => _AllAlbumsScreenState();
}

class _AllAlbumsScreenState extends State<AllAlbumsScreen> {
  List<Album> _albums = [];
  bool _isLoading = true;
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _loadCachedData();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {}

  Future<void> _loadCachedData() async {
    final libraryProvider = Provider.of<LibraryProvider>(
      context,
      listen: false,
    );

    await libraryProvider.ensureLibraryLoaded();

    if (mounted) {
      setState(() {
        _albums = libraryProvider.cachedAllAlbums;
        _isLoading = false;
      });
    }
  }

  Future<void> _refreshAlbums() async {
    final libraryProvider = Provider.of<LibraryProvider>(context, listen: false);
    await libraryProvider.ensureLibraryLoaded();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final providerAlbums = context.select<LibraryProvider, List<Album>>(
      (provider) => provider.cachedAllAlbums,
    );

    if (!_isLoading && !identical(providerAlbums, _albums)) {
      _albums = providerAlbums;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _albums.isEmpty ? 'All Albums' : 'All Albums (${_albums.length})',
        ),
        backgroundColor: isDark ? AppTheme.darkBackground : Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _albums.isEmpty
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.album_outlined, size: 64, color: Colors.grey[600]),
                  const SizedBox(height: 16),
                  Text(
                    'No albums found',
                    style: TextStyle(fontSize: 16, color: Colors.grey[600]),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: _refreshAlbums,
              child: GridView.builder(
                controller: _scrollController,
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  childAspectRatio: 0.7,
                  crossAxisSpacing: 16,
                  mainAxisSpacing: 16,
                ),
                itemCount: _albums.length,
                itemBuilder: (context, index) {
                  final album = _albums[index];
                  return AlbumCard(
                    album: album,
                    size: double.infinity,
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => AlbumScreen(albumId: album.id),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
    );
  }
}
