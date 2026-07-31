import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import '../audio.dart';
import '../main.dart';
import '../widgets.dart';
import 'processing_screen.dart';

/// Waveform, three sliders, and the Generate button.
class EditorScreen extends StatefulWidget {
  const EditorScreen({required this.inputPath, super.key});

  final String inputPath;

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

class _EditorScreenState extends State<EditorScreen> {
  final AudioPlayer _player = AudioPlayer();

  Duration _position = Duration.zero;
  Duration? _duration;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final Duration? duration = await _player.setFilePath(widget.inputPath);
      if (!mounted) return;
      setState(() => _duration = duration);
    } catch (_) {
      if (!mounted) return;
      showMessage(context, 'This file could not be played.');
    }

    // Keep the waveform and timecode in sync with playback.
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
    // Releasing the player frees the native decoder and the audio focus claim.
    _player.dispose();
    super.dispose();
  }

  Future<void> _togglePlay() async {
    if (_player.playing) {
      await _player.pause();
      return;
    }
    // Restart from the top rather than refusing to replay a finished track.
    if (_player.processingState == ProcessingState.completed) {
      await _player.seek(Duration.zero);
    }
    // Mirror the preset tempo so the preview roughly matches the export. The
    // reverb and bass only exist in the FFmpeg render.
    await _player.setSpeed(Audio.presetSlow);
    await _player.play();
  }

  Future<void> _generate() async {
    await _player.pause();
    if (!mounted) return;

    final String name = Audio.fileNameOf(
      widget.inputPath,
      withExtension: false,
    );

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ProcessingScreen(
          inputPath: widget.inputPath,
          name: '$name (Slowed + Reverb)',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Duration? duration = _duration;
    final double progress = (duration == null || duration.inMilliseconds == 0)
        ? 0
        : (_position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    return Scaffold(
      appBar: AppBar(title: const Text('Editor')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        children: <Widget>[
          // ---- File + waveform ---------------------------------------
          SoftCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    ArtworkTile(
                      seed: Audio.fileNameOf(widget.inputPath),
                      size: 48,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            Audio.fileNameOf(
                              widget.inputPath,
                              withExtension: false,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 14.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            formatDuration(duration),
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: kTextMuted,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton.filled(
                      onPressed: _togglePlay,
                      icon: Icon(
                        _playing
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      style: IconButton.styleFrom(
                        backgroundColor: kPrimary,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                WaveformBar(
                  seed: widget.inputPath,
                  progress: progress,
                  onSeek: duration == null
                      ? null
                      : (double value) => _player.seek(
                          Duration(
                            milliseconds: (duration.inMilliseconds * value)
                                .round(),
                          ),
                        ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: <Widget>[
                    Text(
                      formatDuration(_position),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: kTextMuted,
                        fontFeatures: <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                    const Spacer(),
                    Text(
                      formatDuration(
                        duration == null ? null : duration - _position,
                      ),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: kTextMuted,
                        fontFeatures: <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // ---- The preset that will be applied ------------------------
          // Read-only. The values are fixed (see Audio.presetSlow and friends)
          // so the user never has to tune anything — they just hit Generate.
          const _PresetSummary(),
        ],
      ),

      // ---- Generate ------------------------------------------------
      bottomSheet: Container(
        color: kBackground,
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: GradientButton(
          label: 'Generate',
          icon: Icons.auto_awesome_rounded,
          onPressed: _generate,
        ),
      ),
    );
  }
}

/// Shows the fixed preset the export will use.
///
/// Read-only on purpose: the values are tuned once in [Audio] and the user
/// just presses Generate. Showing them anyway sets the expectation of what the
/// output will sound like, which an unexplained Generate button does not.
class _PresetSummary extends StatelessWidget {
  const _PresetSummary();

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: kBrandGradient,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: const Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      'Slow + Reverb',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Tuned preset — nothing to adjust',
                      style: TextStyle(fontSize: 12.5, color: kTextMuted),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: <Widget>[
              _PresetChip(
                label: 'Slow',
                value: '${Audio.presetSlow.toStringAsFixed(2)}x',
              ),
              const SizedBox(width: 8),
              _PresetChip(
                label: 'Reverb',
                value: '${(Audio.presetReverb * 100).round()}%',
              ),
              const SizedBox(width: 8),
              _PresetChip(
                label: 'Bass',
                value: '${(Audio.presetBass * 100).round()}%',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// One read-only value pill.
class _PresetChip extends StatelessWidget {
  const _PresetChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF2FF),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: <Widget>[
            Text(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Color(0xFF4F46E5),
                fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                color: kTextMuted,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
