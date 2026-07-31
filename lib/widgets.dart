import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'main.dart';

/// The Slow Vibes logo.
///
/// Loads `assets/images/logo.png`. To rebrand, replace that one file — nothing
/// else needs editing. If it is missing or unreadable the painted waveform mark
/// below is drawn instead, so a bad asset can never show a broken-image box.
class AppLogo extends StatelessWidget {
  const AppLogo({this.size = 44, super.key});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.28),
        child: Image.asset(
          'assets/images/logo.png',
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
          errorBuilder:
              (BuildContext context, Object error, StackTrace? stack) =>
                  _PaintedLogo(size: size),
        ),
      ),
    );
  }
}

/// Fallback mark, drawn only when the logo asset cannot be loaded.
class _PaintedLogo extends StatelessWidget {
  const _PaintedLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: kBrandGradient,
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: CustomPaint(painter: _LogoPainter(), size: Size.square(size)),
    );
  }
}

class _LogoPainter extends CustomPainter {
  /// Relative bar heights — a wave that peaks left of centre and trails off.
  static const List<double> _heights = <double>[0.3, 0.58, 1.0, 0.74, 0.4];

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;

    // Bars sit inside the middle 60% so the tile keeps optical padding.
    final double usable = size.width * 0.6;
    final double left = (size.width - usable) / 2;
    final double slot = usable / _heights.length;
    final double barWidth = slot * 0.5;
    final double maxHeight = size.height * 0.5;
    final double centreY = size.height / 2;
    final Paint paint = Paint()..color = Colors.white;

    for (int i = 0; i < _heights.length; i++) {
      final double height = maxHeight * _heights[i];
      final double x = left + i * slot + (slot - barWidth) / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, centreY - height / 2, barWidth, height),
          Radius.circular(barWidth / 2),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(_LogoPainter oldDelegate) => false;
}

/// The primary button: gradient fill, coloured glow, Material ripple on top.
class GradientButton extends StatelessWidget {
  const GradientButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.height = 56,
    super.key,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final double height;

  @override
  Widget build(BuildContext context) {
    final bool enabled = onPressed != null;

    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: enabled ? kBrandGradient : null,
        color: enabled ? null : kDivider,
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: enabled
            ? <BoxShadow>[
                BoxShadow(
                  color: kPrimary.withValues(alpha: 0.34),
                  blurRadius: 22,
                  offset: const Offset(0, 10),
                  spreadRadius: -6,
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(kRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(kRadius),
          splashColor: Colors.white.withValues(alpha: 0.18),
          child: Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(
                    icon,
                    size: 21,
                    color: enabled ? Colors.white : kTextFaint,
                  ),
                  const SizedBox(width: 10),
                ],
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: enabled ? Colors.white : kTextFaint,
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

/// White surface, 22px corners, soft shadow. Used for every card in the app.
class SoftCard extends StatelessWidget {
  const SoftCard({
    required this.child,
    this.onTap,
    this.padding = const EdgeInsets.all(18),
    super.key,
  });

  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: kSurface,
        borderRadius: BorderRadius.circular(kRadius),
        boxShadow: kSoftShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(kRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(kRadius),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

/// Square album-art stand-in with a gradient picked from the song name.
///
/// The app never reads embedded cover art, so each song gets a stable
/// generated tile instead — hashing the name means a song always looks the
/// same, which makes the lists feel like a real music app.
class ArtworkTile extends StatelessWidget {
  const ArtworkTile({required this.seed, this.size = 54, super.key});

  final String seed;
  final double size;

  static const List<List<Color>> _ramps = <List<Color>>[
    <Color>[Color(0xFF6366F1), Color(0xFF8B5CF6)],
    <Color>[Color(0xFF8B5CF6), Color(0xFFD946EF)],
    <Color>[Color(0xFF0EA5E9), Color(0xFF6366F1)],
    <Color>[Color(0xFF14B8A6), Color(0xFF0EA5E9)],
    <Color>[Color(0xFFF59E0B), Color(0xFFEF4444)],
    <Color>[Color(0xFFEC4899), Color(0xFF8B5CF6)],
  ];

  @override
  Widget build(BuildContext context) {
    final List<Color> ramp = _ramps[seed.hashCode.abs() % _ramps.length];

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: ramp,
        ),
        borderRadius: BorderRadius.circular(size * 0.28),
      ),
      child: Icon(
        Icons.music_note_rounded,
        color: Colors.white,
        size: size * 0.44,
      ),
    );
  }
}

/// A waveform with a gradient-filled played portion, tappable to seek.
///
/// The bar heights are generated from the file path rather than decoded from
/// the audio: reading real amplitudes needs a native extraction pass, and this
/// build deliberately has no waveform package. The shape is stable per file, so
/// it reads as that song's waveform even though it is synthetic.
class WaveformBar extends StatelessWidget {
  const WaveformBar({
    required this.seed,
    required this.progress,
    this.height = 96,
    this.onSeek,
    super.key,
  });

  final String seed;

  /// 0–1 playback position.
  final double progress;

  final double height;

  /// Called with a 0–1 position when the user taps or drags.
  final ValueChanged<double>? onSeek;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final double width = constraints.maxWidth;

        void report(Offset local) {
          if (width <= 0) return;
          onSeek?.call((local.dx / width).clamp(0.0, 1.0));
        }

        final Widget canvas = SizedBox(
          height: height,
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _WaveformPainter(
                samples: _samplesFor(seed),
                progress: progress.clamp(0.0, 1.0),
              ),
            ),
          ),
        );

        if (onSeek == null) return canvas;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (TapDownDetails d) => report(d.localPosition),
          onHorizontalDragUpdate: (DragUpdateDetails d) =>
              report(d.localPosition),
          child: canvas,
        );
      },
    );
  }

  /// Cached so the list is not rebuilt on every playback frame.
  static final Map<String, List<double>> _cache = <String, List<double>>{};

  static List<double> _samplesFor(String seed) {
    return _cache.putIfAbsent(seed, () {
      final math.Random random = math.Random(seed.isEmpty ? 7 : seed.hashCode);
      // A slow sine envelope with jitter on top reads as audio; pure random
      // noise reads as static.
      return List<double>.generate(90, (int i) {
        final double envelope = 0.45 + 0.32 * math.sin(i / 90 * math.pi * 2.4);
        return (envelope + random.nextDouble() * 0.26).clamp(0.08, 1.0);
      });
    });
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter({required this.samples, required this.progress});

  final List<double> samples;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || samples.isEmpty) return;

    const double barWidth = 3;
    const double gap = 2;
    final int count = math.max(1, (size.width / (barWidth + gap)).floor());
    final double centreY = size.height / 2;
    final double playedX = size.width * progress;

    // One shader across the full width, so the gradient runs along the
    // waveform instead of restarting inside each bar.
    final Paint played = Paint()
      ..shader = const LinearGradient(
        colors: <Color>[kPrimary, kAccent],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    final Paint idle = Paint()..color = const Color(0xFFD8DEE9);

    for (int i = 0; i < count; i++) {
      // Map the fixed sample list onto however many bars fit this width.
      final double amplitude =
          samples[(i * samples.length ~/ count).clamp(0, samples.length - 1)];
      final double half = centreY * amplitude;
      final double x = i * (barWidth + gap);

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, centreY - half, barWidth, half * 2),
          const Radius.circular(barWidth / 2),
        ),
        x + barWidth <= playedX ? played : idle,
      );
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      !identical(oldDelegate.samples, samples);
}

/// Labelled slider with a live value readout on the right.
class EffectSlider extends StatelessWidget {
  const EffectSlider({
    required this.label,
    required this.icon,
    required this.value,
    required this.min,
    required this.max,
    required this.readout,
    required this.onChanged,
    super.key,
  });

  final String label;
  final IconData icon;
  final double value;
  final double min;
  final double max;

  /// Formatted value, e.g. `0.85x` or `40%`.
  final String readout;

  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Icon(icon, size: 19, color: kPrimary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Container(
              // Fixed width so a changing number never reflows the row.
              constraints: const BoxConstraints(minWidth: 58),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF2FF),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                readout,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF4F46E5),
                  // Tabular figures stop the readout jittering as it changes.
                  fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          label: readout,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Centred icon + message, used for the empty Home and Library states.
class EmptyState extends StatelessWidget {
  const EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    super.key,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 40),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: const Color(0xFFEEF2FF),
              borderRadius: BorderRadius.circular(24),
            ),
            child: Icon(icon, size: 34, color: kPrimary),
          ),
          const SizedBox(height: 20),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13.5,
              color: kTextMuted,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Shows a floating snackbar. Safe to call after an await.
void showMessage(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(message)));
}
