import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../audio.dart';
import '../main.dart';
import 'preview_screen.dart';

/// Circular progress plus a looping wave animation while FFmpeg renders.
class ProcessingScreen extends StatefulWidget {
  const ProcessingScreen({
    required this.inputPath,
    required this.name,
    required this.slow,
    required this.reverb,
    required this.bass,
    super.key,
  });

  final String inputPath;
  final String name;
  final double slow;
  final double reverb;
  final double bass;

  @override
  State<ProcessingScreen> createState() => _ProcessingScreenState();
}

class _ProcessingScreenState extends State<ProcessingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _wave = AnimationController(
    duration: const Duration(milliseconds: 2400),
    vsync: this,
  )..repeat();

  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _run();
  }

  @override
  void dispose() {
    _wave.dispose();
    super.dispose();
  }

  Future<void> _run() async {
    try {
      final String output = await Audio.render(
        inputPath: widget.inputPath,
        name: widget.name,
        slow: widget.slow,
        reverb: widget.reverb,
        bass: widget.bass,
        onProgress: (double value) {
          if (!mounted) return;
          // Never let the bar go backwards — it reads as a bug even when the
          // underlying estimate genuinely improved.
          if (value > _progress) setState(() => _progress = value);
        },
      );

      if (!mounted) return;
      // Replace, so backing out of Preview does not land on this screen again.
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PreviewScreen(renderPath: output, name: widget.name),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$error')));
    }
  }

  Future<void> _cancel() async {
    await Audio.cancel();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final int percent = (_progress * 100).round();

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              const Spacer(),

              // ---- Progress ring ---------------------------------------
              SizedBox(
                width: 190,
                height: 190,
                child: Stack(
                  alignment: Alignment.center,
                  children: <Widget>[
                    SizedBox.expand(
                      child: CircularProgressIndicator(
                        // Spin freely until FFmpeg reports real numbers;
                        // sitting at 0% would look stuck.
                        value: _progress <= 0.01 ? null : _progress,
                        strokeWidth: 9,
                        strokeCap: StrokeCap.round,
                        backgroundColor: kDivider,
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          kPrimary,
                        ),
                      ),
                    ),
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Text(
                          _progress <= 0.01 ? '—' : '$percent%',
                          style: const TextStyle(
                            fontSize: 38,
                            fontWeight: FontWeight.w700,
                            letterSpacing: -1,
                            fontFeatures: <FontFeature>[
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        const SizedBox(height: 2),
                        const Text(
                          'rendering',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: kTextMuted,
                            letterSpacing: 0.4,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 40),

              const Text(
                'Transforming your music',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              const Text(
                'Please wait while we add the slow and reverb.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: kTextMuted, height: 1.5),
              ),

              const Spacer(),

              // ---- Wave animation -------------------------------------
              RepaintBoundary(
                child: AnimatedBuilder(
                  animation: _wave,
                  builder: (BuildContext context, _) => CustomPaint(
                    size: const Size(double.infinity, 90),
                    painter: _WavePainter(
                      phase: _wave.value,
                      progress: _progress,
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),
              TextButton(onPressed: _cancel, child: const Text('Cancel')),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

/// Three sine waves at different speeds. Their interference is what keeps the
/// motion from looking like a short repeating loop.
class _WavePainter extends CustomPainter {
  const _WavePainter({required this.phase, required this.progress});

  final double phase;
  final double progress;

  /// (frequency, amplitude scale, phase speed) per layer.
  static const List<List<double>> _layers = <List<double>>[
    <double>[1.4, 1.0, 1.0],
    <double>[2.1, 0.65, -1.6],
    <double>[3.3, 0.42, 2.3],
  ];

  static const List<double> _opacities = <double>[0.16, 0.24, 0.42];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // Waves swell as the render nears completion.
    final double gain = 16 * (0.6 + progress * 0.6);

    for (int i = 0; i < _layers.length; i++) {
      final List<double> layer = _layers[i];
      final Path path = Path();
      final double midY = size.height / 2;
      final double shift = phase * 2 * math.pi * layer[2];

      path.moveTo(0, midY);
      // 2px steps: finer is invisible at this amplitude and just costs
      // path segments every frame.
      for (double x = 0; x <= size.width; x += 2) {
        final double t = x / size.width;
        final double y =
            midY +
            math.sin(t * layer[0] * 2 * math.pi + shift) * gain * layer[1];
        path.lineTo(x, y);
      }
      path
        ..lineTo(size.width, size.height)
        ..lineTo(0, size.height)
        ..close();

      canvas.drawPath(
        path,
        Paint()
          ..color = (i == 2 ? kPrimary : kAccent).withValues(
            alpha: _opacities[i],
          ),
      );
    }
  }

  @override
  bool shouldRepaint(_WavePainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.progress != progress;
}
