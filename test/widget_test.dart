import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:slow_vibes/audio.dart';
import 'package:slow_vibes/widgets.dart';

/// Wraps a widget in the minimum needed to pump it.
Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  group('formatDuration', () {
    test('pads seconds', () {
      expect(formatDuration(const Duration(seconds: 9)), '0:09');
      expect(formatDuration(const Duration(minutes: 3, seconds: 24)), '3:24');
    });

    test('adds an hours field only past an hour', () {
      expect(formatDuration(const Duration(minutes: 59)), '59:00');
      expect(formatDuration(const Duration(hours: 1, minutes: 5)), '1:05:00');
    });

    test('clamps null and negatives to zero', () {
      expect(formatDuration(null), '0:00');
      expect(formatDuration(const Duration(seconds: -5)), '0:00');
    });
  });

  group('formatSize', () {
    test('scales units', () {
      expect(formatSize(512), '512 B');
      expect(formatSize(2048), '2 KB');
      expect(formatSize(5 * 1024 * 1024), '5.0 MB');
    });
  });

  group('Audio.buildFilters', () {
    test('resamples before asetrate so the slow factor is exact', () {
      // asetrate reinterprets samples at a new rate, so it only produces the
      // requested factor if the incoming rate is known. A 48 kHz source without
      // the leading aresample would be slowed by the wrong amount.
      final String chain = Audio.buildFilters(slow: 0.5, reverb: 0, bass: 0);
      expect(
        chain.indexOf('aresample=44100'),
        lessThan(chain.indexOf('asetrate')),
      );
      expect(chain, contains('asetrate=22050'));
    });

    test('omits bass and reverb when they are off', () {
      final String chain = Audio.buildFilters(slow: 1, reverb: 0, bass: 0);
      expect(chain, isNot(contains('bass=')));
      expect(chain, isNot(contains('aecho=')));
    });

    test('adds bass and reverb when they are on', () {
      final String chain = Audio.buildFilters(
        slow: 0.8,
        reverb: 0.5,
        bass: 0.5,
      );
      expect(chain, contains('bass=g=6.0'));
      expect(chain, contains('aecho='));
    });

    test('always ends with a limiter', () {
      // Bass plus reverb regularly sums past full scale; without the limiter
      // the export clips.
      expect(
        Audio.buildFilters(slow: 0.7, reverb: 1, bass: 1),
        endsWith('alimiter=limit=0.93'),
      );
    });
  });

  group('Audio.fileNameOf', () {
    test('strips directories and optionally the extension', () {
      expect(Audio.fileNameOf('/music/My Song.mp3'), 'My Song.mp3');
      expect(
        Audio.fileNameOf('/music/My Song.mp3', withExtension: false),
        'My Song',
      );
      expect(Audio.fileNameOf(r'C:\music\Track.wav'), 'Track.wav');
    });
  });

  // These pump the real widgets, which exercises the build methods and the
  // CustomPainters. Analysis cannot catch a painter that throws on an empty
  // size or a layout that overflows.
  group('widgets render', () {
    testWidgets('AppLogo paints', (WidgetTester tester) async {
      await tester.pumpWidget(_host(const AppLogo()));
      expect(tester.takeException(), isNull);
    });

    testWidgets('GradientButton shows its label and fires', (
      WidgetTester tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        _host(
          GradientButton(
            label: 'Generate',
            icon: Icons.auto_awesome_rounded,
            onPressed: () => taps++,
          ),
        ),
      );
      expect(find.text('Generate'), findsOneWidget);
      await tester.tap(find.text('Generate'));
      expect(taps, 1);
    });

    testWidgets('GradientButton is inert when disabled', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(const GradientButton(label: 'Save', onPressed: null)),
      );
      await tester.tap(find.text('Save'));
      expect(tester.takeException(), isNull);
    });

    testWidgets('WaveformBar paints and reports seeks', (
      WidgetTester tester,
    ) async {
      double? seeked;
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 300,
            child: WaveformBar(
              seed: 'track.mp3',
              progress: 0.4,
              onSeek: (double v) => seeked = v,
            ),
          ),
        ),
      );
      expect(tester.takeException(), isNull);

      // Tap the middle; the reported position should be about halfway.
      await tester.tapAt(tester.getCenter(find.byType(WaveformBar)));
      expect(seeked, isNotNull);
      expect(seeked, closeTo(0.5, 0.05));
    });

    testWidgets('WaveformBar survives a zero-width parent', (
      WidgetTester tester,
    ) async {
      // A painter that divides by width would throw here.
      await tester.pumpWidget(
        _host(
          const SizedBox(
            width: 0,
            child: WaveformBar(seed: 'x', progress: 0.5),
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('EffectSlider shows its readout and reports changes', (
      WidgetTester tester,
    ) async {
      double value = 0.85;
      await tester.pumpWidget(
        _host(
          SizedBox(
            width: 320,
            child: EffectSlider(
              label: 'Slow',
              icon: Icons.slow_motion_video_rounded,
              value: value,
              min: 0.5,
              max: 1.0,
              readout: '0.85x',
              onChanged: (double v) => value = v,
            ),
          ),
        ),
      );
      expect(find.text('Slow'), findsOneWidget);
      expect(find.text('0.85x'), findsOneWidget);

      await tester.drag(find.byType(Slider), const Offset(-60, 0));
      expect(value, lessThan(0.85));
    });

    testWidgets('ArtworkTile gives the same colour for the same name', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        _host(
          const Column(
            children: <Widget>[
              ArtworkTile(seed: 'Midnight'),
              ArtworkTile(seed: 'Midnight'),
            ],
          ),
        ),
      );
      final List<BoxDecoration> decorations = tester
          .widgetList<Container>(find.byType(Container))
          .map((Container c) => c.decoration)
          .whereType<BoxDecoration>()
          .toList();
      expect(decorations, hasLength(2));
      expect(decorations.first.gradient, decorations.last.gradient);
    });

    testWidgets('EmptyState renders its copy', (WidgetTester tester) async {
      await tester.pumpWidget(
        _host(
          const EmptyState(
            icon: Icons.library_music_rounded,
            title: 'Your library is empty',
            message: 'Songs you save show up here.',
          ),
        ),
      );
      expect(find.text('Your library is empty'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
