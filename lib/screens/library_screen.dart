import 'package:flutter/material.dart';

import '../audio.dart';
import '../main.dart';
import '../widgets.dart';
import 'preview_screen.dart';

/// Exported songs, with search, delete and share.
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final TextEditingController _search = TextEditingController();

  List<Song> _songs = <Song>[];
  bool _loading = true;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final List<Song> songs = await Audio.listSongs();
    if (!mounted) return;
    setState(() {
      _songs = songs;
      _loading = false;
    });
  }

  /// Filtered in the build path rather than stored, so there is no second copy
  /// of the list to keep in sync.
  List<Song> get _visible {
    final String needle = _query.trim().toLowerCase();
    if (needle.isEmpty) return _songs;
    return _songs
        .where((Song s) => s.name.toLowerCase().contains(needle))
        .toList();
  }

  Future<void> _delete(Song song) async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Delete this track?'),
            content: Text('"${song.name}" will be removed from your device.'),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                style: TextButton.styleFrom(
                  foregroundColor: const Color(0xFFEF4444),
                ),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed) return;

    await Audio.delete(song.path);
    if (!mounted) return;
    showMessage(context, 'Deleted');
    await _load();
  }

  Future<void> _share(Song song) async {
    try {
      await Audio.share(song.path, song.name);
    } catch (_) {
      if (!mounted) return;
      showMessage(context, 'Sharing failed.');
    }
  }

  Future<void> _open(Song song) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => PreviewScreen(
          renderPath: song.path,
          name: song.name,
          alreadySaved: true,
        ),
      ),
    );
    // Preview can delete the track, so refresh on return.
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final List<Song> visible = _visible;

    return Scaffold(
      appBar: AppBar(title: const Text('Library')),
      body: Column(
        children: <Widget>[
          // ---- Search ------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: TextField(
              controller: _search,
              onChanged: (String value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Search your tracks',
                prefixIcon: const Icon(Icons.search_rounded, color: kTextFaint),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(Icons.close_rounded, size: 20),
                        color: kTextFaint,
                        onPressed: () {
                          _search.clear();
                          setState(() => _query = '');
                        },
                      ),
              ),
            ),
          ),

          if (!_loading && _songs.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Row(
                children: <Widget>[
                  Text(
                    '${visible.length} '
                    '${visible.length == 1 ? 'track' : 'tracks'}',
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: kTextFaint,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.3,
                    ),
                  ),
                ],
              ),
            ),

          // ---- List --------------------------------------------------
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _songs.isEmpty
                ? const Center(
                    child: EmptyState(
                      icon: Icons.library_music_rounded,
                      title: 'Your library is empty',
                      message:
                          'Songs you generate and save will be collected '
                          'here.',
                    ),
                  )
                : visible.isEmpty
                ? const Center(
                    child: EmptyState(
                      icon: Icons.search_off_rounded,
                      title: 'No matches',
                      message: 'Try a different name, or clear the search.',
                    ),
                  )
                : RefreshIndicator(
                    onRefresh: _load,
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
                      itemCount: visible.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 12),
                      itemBuilder: (BuildContext context, int index) {
                        final Song song = visible[index];
                        return _SongTile(
                          song: song,
                          onTap: () => _open(song),
                          onShare: () => _share(song),
                          onDelete: () => _delete(song),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// One library row: artwork, name, size, and share/delete buttons.
class _SongTile extends StatelessWidget {
  const _SongTile({
    required this.song,
    required this.onTap,
    required this.onShare,
    required this.onDelete,
  });

  final Song song;
  final VoidCallback onTap;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
      child: Row(
        children: <Widget>[
          ArtworkTile(seed: song.name),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  song.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${formatSize(song.sizeBytes)} · '
                  '${Audio.extensionOf(song.path).toUpperCase()}',
                  style: const TextStyle(fontSize: 12.5, color: kTextMuted),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: onShare,
            icon: const Icon(Icons.ios_share_rounded, size: 20),
            color: kTextMuted,
            tooltip: 'Share',
          ),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 21),
            color: const Color(0xFFEF4444),
            tooltip: 'Delete',
          ),
        ],
      ),
    );
  }
}
