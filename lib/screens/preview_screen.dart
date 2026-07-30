import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../audio.dart';
import '../main.dart';
import '../widgets.dart';

/// Play/pause, seekbar, and Save / Share / Delete for a finished render.
///
/// The render arrives in a scratch folder. **Save** moves it into the library;
/// **Delete** discards it. Leaving without saving keeps it in scratch, which the
/// OS clears on its own.
class PreviewScreen extends StatefulWidget {
  const PreviewScreen({
    required this.renderPath,
    required this.name,
    this.alreadySaved = false,
    super.key,
  });

  final String renderPath;
  final String name;

  /// True when opened from the Library, where the file is already saved.
  /// Without this the Save button would copy it a second time as "name (2)".
  final bool alreadySaved;

  @override
  State<PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<PreviewScreen> {
  final AudioPlayer _player = AudioPlayer();

  Duration _position = Duration.zero;
  Duration? _duration;
  bool _playing = false;

  /// Path of the file being previewed. Changes once it is saved.
  late String _path = widget.renderPath;
  late bool _saved = widget.alreadySaved;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final Duration? duration = await _player.setFilePath(_path);
      if (!mounted) return;
      setState(() => _duration = duration);
    } catch (_) {
      if (!mounted) return;
      showMessage(context, 'This track could not be played.');
      return;
    }

    _player.positionStream.listen((Duration value) {
      if (!mounted) return;
      setState(() => _position = value);
    });
    _player.playerStateStream.listen((PlayerState state) {
      if (!mounted) return;
      setState(() {
        _playing =
            state.playing && state.processingState != ProcessingState.completed;
      });
    });
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_player.playing) {
      await _player.pause();
      return;
    }
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    await _player.play();
  }

  Future<void> _save() async {
    if (_saved || _busy) return;
    setState(() => _busy = true);
    try {
      final Song song = await Audio.saveToLibrary(_path, widget.name);
      // The file moved, so the player must be pointed at the new location or
      // playback breaks the moment it needs to read again.
      await _player.setFilePath(song.path);
      if (!mounted) return;
      setState(() {
        _path = song.path;
        _saved = true;
      });
      showMessage(context, 'Saved to your library');
    } catch (error) {
      if (!mounted) return;
      showMessage(context, 'Could not save: $error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    try {
      await Audio.share(_path, widget.name);
    } catch (_) {
      if (!mounted) return;
      showMessage(context, 'Sharing failed.');
    }
  }

  Future<void> _delete() async {
    final bool confirmed =
        await showDialog<bool>(
          context: context,
          builder: (BuildContext context) => AlertDialog(
            title: const Text('Delete this track?'),
            content: const Text('This removes the file from your device.'),
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

    // Stop playback before deleting, or the native player keeps a handle open.
    await _player.stop();
    await Audio.delete(_path);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final Duration? duration = _duration;
    final double maxMs = (duration?.inMilliseconds ?? 0).toDouble();
    final double valueMs = _position.inMilliseconds.clamp(0, maxMs).toDouble();

    return Scaffold(
      appBar: AppBar(title: const Text('Preview')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
        children: <Widget>[
          const SizedBox(height: 12),

          // ---- Artwork -----------------------------------------------
          Center(child: ArtworkTile(seed: widget.name, size: 180)),

          const SizedBox(height: 28),

          Text(
            widget.name,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              height: 1.3,
              letterSpacing: -0.4,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _saved ? 'Saved to library' : 'Not saved yet',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13,
              color: _saved ? const Color(0xFF10B981) : kTextMuted,
              fontWeight: FontWeight.w500,
            ),
          ),

          const SizedBox(height: 28),

          WaveformBar(seed: _path, progress: maxMs == 0 ? 0 : valueMs / maxMs),

          const SizedBox(height: 8),

          // ---- Seekbar -----------------------------------------------
          Slider(
            value: valueMs,
            max: maxMs == 0 ? 1 : maxMs,
            onChanged: maxMs == 0
                ? null
                : (double value) =>
                      _player.seek(Duration(milliseconds: value.round())),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(
              children: <Widget>[
                Text(
                  formatDuration(_position),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: kTextMuted,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
                const Spacer(),
                Text(
                  formatDuration(duration),
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: kTextMuted,
                    fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          // ---- Play / pause ------------------------------------------
          Center(
            child: _BigPlayButton(playing: _playing, onPressed: _togglePlay),
          ),

          const SizedBox(height: 36),

          // ---- Actions -----------------------------------------------
          GradientButton(
            label: _saved ? 'Saved' : 'Save',
            icon: _saved ? Icons.check_rounded : Icons.download_rounded,
            onPressed: _saved || _busy ? null : _save,
          ),
          const SizedBox(height: 12),
          Row(
            children: <Widget>[
              Expanded(
                child: _OutlineAction(
                  label: 'Share',
                  icon: Icons.ios_share_rounded,
                  onPressed: _share,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _OutlineAction(
                  label: 'Delete',
                  icon: Icons.delete_outline_rounded,
                  colour: const Color(0xFFEF4444),
                  onPressed: _delete,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Large circular play/pause with a gradient fill.
class _BigPlayButton extends StatelessWidget {
  const _BigPlayButton({required this.playing, required this.onPressed});

  final bool playing;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        gradient: kBrandGradient,
        shape: BoxShape.circle,
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: kPrimary.withValues(alpha: 0.38),
            blurRadius: 26,
            offset: const Offset(0, 12),
            spreadRadius: -6,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          splashColor: Colors.white.withValues(alpha: 0.2),
          child: Icon(
            playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
            color: Colors.white,
            size: 36,
          ),
        ),
      ),
    );
  }
}

/// A quieter secondary action: white surface, tinted hairline.
class _OutlineAction extends StatelessWidget {
  const _OutlineAction({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.colour = kPrimary,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 19),
        label: Text(label),
        style: OutlinedButton.styleFrom(
          foregroundColor: colour,
          backgroundColor: kSurface,
          side: BorderSide(color: colour.withValues(alpha: 0.25), width: 1.4),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kRadius),
          ),
          textStyle: const TextStyle(
            fontSize: 14.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
