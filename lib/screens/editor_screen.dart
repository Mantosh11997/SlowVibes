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

  double _slow = 0.85;
  double _reverb = 0.35;
  double _bass = 0.25;

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
    // Mirror the Slow slider so the preview roughly matches the export. The
    // reverb and bass only exist in the FFmpeg render.
    await _player.setSpeed(_slow);
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
          name: '$name (Slowed ${_slow.toStringAsFixed(2)}x)',
          slow: _slow,
          reverb: _reverb,
          bass: _bass,
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

          // ---- Sliders -----------------------------------------------
          SoftCard(
            padding: const EdgeInsets.fromLTRB(18, 20, 18, 8),
            child: Column(
              children: <Widget>[
                EffectSlider(
                  label: 'Slow',
                  icon: Icons.slow_motion_video_rounded,
                  value: _slow,
                  min: 0.5,
                  max: 1.0,
                  readout: '${_slow.toStringAsFixed(2)}x',
                  onChanged: (double v) {
                    setState(() => _slow = v);
                    // Follow the slider live if something is already playing.
                    if (_player.playing) {
                      _player.setSpeed(v);
                    }
                  },
                ),
                EffectSlider(
                  label: 'Reverb',
                  icon: Icons.blur_on_rounded,
                  value: _reverb,
                  min: 0,
                  max: 1,
                  readout: '${(_reverb * 100).round()}%',
                  onChanged: (double v) => setState(() => _reverb = v),
                ),
                EffectSlider(
                  label: 'Bass',
                  icon: Icons.graphic_eq_rounded,
                  value: _bass,
                  min: 0,
                  max: 1,
                  readout: '${(_bass * 100).round()}%',
                  onChanged: (double v) => setState(() => _bass = v),
                ),
              ],
            ),
          ),

          const SizedBox(height: 14),

          Text(
            'Playback preview only follows the Slow slider. Reverb and bass '
            'are applied when you generate.',
            style: const TextStyle(
              fontSize: 12,
              color: kTextFaint,
              height: 1.45,
            ),
          ),
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
