import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../audio.dart';
import '../main.dart';
import '../widgets.dart';
import 'editor_screen.dart';
import 'library_screen.dart';
import 'preview_screen.dart';

/// Logo, title, Upload Music button, and the most recent exports.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Song> _recent = <Song>[];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRecent();
  }

  Future<void> _loadRecent() async {
    final List<Song> songs = await Audio.listSongs();
    if (!mounted) return;
    setState(() {
      // Home shows a short list; the Library screen shows everything.
      _recent = songs.take(4).toList();
      _loading = false;
    });
  }

  Future<void> _pickFile() async {
    // No permission request needed: this opens the system document picker,
    // which grants access to just the file the user taps.
    final FilePickerResult? result = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: Audio.pickerExtensions,
    );

    final String? path = result?.files.single.path;
    if (path == null) return; // User backed out.
    if (!mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => EditorScreen(inputPath: path)),
    );
    // Coming back from the editor may have added a song.
    await _loadRecent();
  }

  Future<void> _openLibrary() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const LibraryScreen()));
    await _loadRecent();
  }

  Future<void> _openSong(Song song) async {
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
    await _loadRecent();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _loadRecent,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
            children: <Widget>[
              // ---- Header ----------------------------------------------
              Row(
                children: <Widget>[
                  const AppLogo(),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Text(
                      'Slow Vibes',
                      style: TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.4,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: _openLibrary,
                    icon: const Icon(Icons.library_music_rounded),
                    tooltip: 'Library',
                    color: kTextMuted,
                  ),
                ],
              ),

              const SizedBox(height: 32),

              const Text(
                'Transform your music',
                style: TextStyle(
                  fontSize: 29,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  letterSpacing: -0.8,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Turn any song into slow + reverb audio.',
                style: TextStyle(fontSize: 15, color: kTextMuted, height: 1.5),
              ),

              const SizedBox(height: 28),

              // ---- Upload card -----------------------------------------
              _UploadCard(onTap: _pickFile),

              const SizedBox(height: 36),

              // ---- Recent files ----------------------------------------
              Row(
                children: <Widget>[
                  const Expanded(
                    child: Text(
                      'Recent files',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (_recent.isNotEmpty)
                    TextButton(
                      onPressed: _openLibrary,
                      child: const Text('See all'),
                    ),
                ],
              ),
              const SizedBox(height: 8),

              if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 40),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_recent.isEmpty)
                const EmptyState(
                  icon: Icons.graphic_eq_rounded,
                  title: 'Nothing here yet',
                  message:
                      'Pick a song above and your finished tracks will show '
                      'up here.',
                )
              else
                for (final Song song in _recent)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _RecentTile(
                      song: song,
                      onTap: () => _openSong(song),
                    ),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The big gradient "Upload Music" panel.
class _UploadCard extends StatelessWidget {
  const _UploadCard({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: kBrandGradient,
        borderRadius: BorderRadius.circular(28),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: kPrimary.withValues(alpha: 0.34),
            blurRadius: 30,
            offset: const Offset(0, 14),
            spreadRadius: -8,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(28),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          splashColor: Colors.white.withValues(alpha: 0.14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              children: <Widget>[
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(
                    Icons.audio_file_rounded,
                    color: Colors.white,
                    size: 30,
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  'Upload Music',
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'MP3 · WAV · AAC · M4A · OGG · FLAC',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w500,
                    color: Colors.white.withValues(alpha: 0.85),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One row in the Recent files list.
class _RecentTile extends StatelessWidget {
  const _RecentTile({required this.song, required this.onTap});

  final Song song;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      onTap: onTap,
      padding: const EdgeInsets.all(12),
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
                  formatSize(song.sizeBytes),
                  style: const TextStyle(fontSize: 12.5, color: kTextMuted),
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right_rounded, color: kTextFaint),
        ],
      ),
    );
  }
}
