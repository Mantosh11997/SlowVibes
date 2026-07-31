import 'dart:async';
import 'dart:io';

import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffmpeg_session.dart';
import 'package:ffmpeg_kit_flutter_new_audio/ffprobe_kit.dart';
import 'package:ffmpeg_kit_flutter_new_audio/media_information_session.dart';
import 'package:ffmpeg_kit_flutter_new_audio/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_audio/statistics.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// One exported song on disk.
class Song {
  Song({
    required this.path,
    required this.name,
    required this.sizeBytes,
    required this.modified,
  });

  final String path;
  final String name;
  final int sizeBytes;
  final DateTime modified;

  factory Song.fromFile(File file) {
    final FileStat stat = file.statSync();
    return Song(
      path: file.path,
      name: Audio.fileNameOf(file.path, withExtension: false),
      sizeBytes: stat.size,
      modified: stat.modified,
    );
  }
}

/// Everything the app does with audio files: pick a folder, run FFmpeg,
/// list exports, delete, share.
///
/// Plain static functions — no state, nothing to wire up.
class Audio {
  Audio._();

  /// Session id of the render in flight, so it can be cancelled.
  static int? _sessionId;

  // -------------------------------------------------------------------------
  // The preset
  // -------------------------------------------------------------------------
  // The app deliberately exposes no controls: these three values are the
  // "Slow Vibes sound". Tune them here and every future export follows.

  /// Playback rate. 0.85 is slow enough to feel unmistakably slowed while
  /// keeping vocals intelligible; below ~0.75 most tracks start to smear.
  static const double presetSlow = 0.85;

  /// Reverb wet amount, 0–1.
  static const double presetReverb = 0.35;

  /// Bass shelf amount, 0–1 (maps to 0–12 dB below 110 Hz).
  static const double presetBass = 0.25;

  // -------------------------------------------------------------------------
  // Folders
  // -------------------------------------------------------------------------

  /// Where saved songs live. Created on first use.
  static Future<Directory> libraryDir() async {
    final Directory base = await getApplicationDocumentsDirectory();
    final Directory dir = Directory('${base.path}/SlowVibes');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Scratch folder for renders that have not been saved yet.
  static Future<Directory> tempDir() async {
    final Directory base = await getTemporaryDirectory();
    final Directory dir = Directory('${base.path}/renders');
    if (!dir.existsSync()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  // -------------------------------------------------------------------------
  // Library
  // -------------------------------------------------------------------------

  /// Every saved song, newest first.
  ///
  /// Reads the folder each time instead of keeping a list in memory, so the
  /// screens can never show a song that is no longer there.
  static Future<List<Song>> listSongs() async {
    final Directory dir = await libraryDir();
    final List<Song> songs = dir
        .listSync()
        .whereType<File>()
        .where((File f) => _audioExtensions.contains(extensionOf(f.path)))
        .map(Song.fromFile)
        .toList();
    songs.sort((Song a, Song b) => b.modified.compareTo(a.modified));
    return songs;
  }

  /// Moves a finished render out of the scratch folder and into the library.
  static Future<Song> saveToLibrary(String renderPath, String name) async {
    final Directory dir = await libraryDir();
    final String extension = extensionOf(renderPath);
    String target = '${dir.path}/$name.$extension';

    // Add a number if that name is taken, so saving twice never overwrites.
    var counter = 2;
    while (File(target).existsSync()) {
      target = '${dir.path}/$name ($counter).$extension';
      counter++;
    }

    final File source = File(renderPath);
    File saved;
    try {
      saved = await source.rename(target);
    } on FileSystemException {
      // rename() fails when temp and documents are on different volumes,
      // which is normal on Android.
      saved = await source.copy(target);
      await source.delete();
    }
    return Song.fromFile(saved);
  }

  static Future<void> delete(String path) async {
    final File file = File(path);
    if (file.existsSync()) {
      await file.delete();
    }
  }

  static Future<void> share(String path, String name) async {
    await SharePlus.instance.share(
      ShareParams(
        files: <XFile>[XFile(path, mimeType: _mimeTypeOf(path))],
        subject: name,
        text: '$name — made with Slow Vibes',
      ),
    );
  }

  // -------------------------------------------------------------------------
  // FFmpeg
  // -------------------------------------------------------------------------

  /// Reads a file's duration. Returns [Duration.zero] if it cannot be read.
  static Future<Duration> durationOf(String path) async {
    final MediaInformationSession session =
        await FFprobeKit.getMediaInformation(path);
    final String? raw = session.getMediaInformation()?.getDuration();
    final double seconds = double.tryParse(raw ?? '') ?? 0;
    if (seconds <= 0) return Duration.zero;
    return Duration(milliseconds: (seconds * 1000).round());
  }

  /// Builds the audio filter chain for the three sliders.
  ///
  /// * `slow`   0.5 – 1.0  playback rate
  /// * `reverb` 0.0 – 1.0  wet amount
  /// * `bass`   0.0 – 1.0  low shelf gain, mapped to 0 – 12 dB
  ///
  /// `asetrate` is what makes the "slowed" sound: it replays the samples at a
  /// lower rate so tempo *and* pitch drop together, the same as playing a
  /// record slower. It only behaves predictably if the incoming rate is known,
  /// so the chain resamples to 44100 first — otherwise a 48 kHz source would be
  /// slowed by the wrong factor.
  ///
  /// Reverb is built from a multi-tap `aecho`. This FFmpeg build has no
  /// convolution reverb, and four decaying taps at uneven spacing give a tail
  /// without the metallic ring that evenly spaced delays produce.
  static String buildFilters({
    required double slow,
    required double reverb,
    required double bass,
  }) {
    const int rate = 44100;
    final List<String> filters = <String>[
      'aresample=$rate',
      'asetrate=${(rate * slow).round()}',
      'aresample=$rate',
    ];

    if (bass > 0.01) {
      final double gain = bass * 12;
      filters.add('bass=g=${gain.toStringAsFixed(1)}:f=110');
    }

    if (reverb > 0.01) {
      // Tap delays in ms, then their decays. Louder wet = louder taps.
      const List<double> delays = <double>[35, 60, 92, 125];
      final double peak = reverb * 0.6;
      final List<String> decays = <String>[
        peak.toStringAsFixed(3),
        (peak * 0.68).toStringAsFixed(3),
        (peak * 0.46).toStringAsFixed(3),
        (peak * 0.3).toStringAsFixed(3),
      ];
      // Pulling the dry signal down as the mix gets wetter keeps the loudness
      // roughly steady, so the reverb slider does not double as a volume knob.
      final double outGain = (1 - reverb * 0.3).clamp(0.4, 1.0);
      filters.add(
        'aecho=1:${outGain.toStringAsFixed(2)}'
        ':${delays.map((double d) => d.round()).join('|')}'
        ':${decays.join('|')}',
      );
    }

    // Bass plus reverb regularly sums past full scale; without this the export
    // clips and sounds crunchy.
    filters.add('alimiter=limit=0.93');

    return filters.join(',');
  }

  /// Renders [inputPath] into the scratch folder and returns the new file path.
  ///
  /// [onProgress] is called with a 0–1 value. FFmpegKit runs the encode on a
  /// native background thread, so the UI keeps animating the whole time.
  ///
  /// Throws a [String] message on failure, which the caller shows in a snackbar.
  static Future<String> render({
    required String inputPath,
    required String name,
    required void Function(double progress) onProgress,
    double slow = presetSlow,
    double reverb = presetReverb,
    double bass = presetBass,
  }) async {
    final Duration sourceDuration = await durationOf(inputPath);
    // Slowing to 0.5x makes the output twice as long; progress is measured
    // against the output length, not the input's.
    final int expectedMs = sourceDuration.inMilliseconds <= 0
        ? 0
        : (sourceDuration.inMilliseconds / slow).round();

    final Directory dir = await tempDir();
    final String output =
        '${dir.path}/${DateTime.now().millisecondsSinceEpoch}.mp3';

    final String filters = buildFilters(slow: slow, reverb: reverb, bass: bass);

    // Passing arguments as a list rather than one command string means paths
    // containing spaces or quotes need no escaping.
    final List<String> args = <String>[
      '-hide_banner',
      '-nostdin',
      '-y',
      '-i', inputPath,
      // Take only the audio. An MP3 with embedded cover art also presents a
      // video stream, and without this the encode fails on it.
      '-map', '0:a:0',
      '-vn',
      '-filter:a', filters,
      '-c:a', 'libmp3lame',
      '-b:a', '192k',
      '-ar', '44100',
      output,
    ];

    // executeWithArgumentsAsync returns as soon as the job is queued, so the
    // completion callback is bridged to a Future here.
    final Completer<ReturnCode?> done = Completer<ReturnCode?>();

    final FFmpegSession session = await FFmpegKit.executeWithArgumentsAsync(
      args,
      (FFmpegSession session) async {
        if (!done.isCompleted) {
          done.complete(await session.getReturnCode());
        }
      },
      null,
      (Statistics stats) {
        if (expectedMs <= 0) return;
        final double value = (stats.getTime() / expectedMs).clamp(0.0, 0.99);
        onProgress(value);
      },
    );
    _sessionId = session.getSessionId();

    final ReturnCode? code = await done.future;
    _sessionId = null;

    if (ReturnCode.isCancel(code)) {
      await delete(output);
      throw 'Export cancelled.';
    }

    if (!ReturnCode.isSuccess(code)) {
      final String? logs = await session.getAllLogsAsString();
      await delete(output);
      throw 'Export failed. ${_lastLine(logs)}';
    }

    // FFmpeg can exit 0 having written nothing useful; a real MP3 is far
    // bigger than 1 KB.
    final File file = File(output);
    if (!file.existsSync() || await file.length() < 1024) {
      await delete(output);
      throw 'Export produced an empty file.';
    }

    onProgress(1);
    return output;
  }

  /// Stops the render in flight.
  static Future<void> cancel() async {
    final int? id = _sessionId;
    if (id == null) return;
    await FFmpegKit.cancel(id);
    _sessionId = null;
  }

  // -------------------------------------------------------------------------
  // Small helpers
  // -------------------------------------------------------------------------

  static const List<String> _audioExtensions = <String>[
    'mp3',
    'wav',
    'aac',
    'm4a',
    'ogg',
    'flac',
  ];

  /// Extensions offered in the file picker.
  static const List<String> pickerExtensions = _audioExtensions;

  static String extensionOf(String path) {
    final int dot = path.lastIndexOf('.');
    if (dot == -1 || dot == path.length - 1) return '';
    return path.substring(dot + 1).toLowerCase();
  }

  static String fileNameOf(String path, {bool withExtension = true}) {
    final String name = path.split(RegExp(r'[/\\]')).last;
    if (withExtension) return name;
    final int dot = name.lastIndexOf('.');
    return dot == -1 ? name : name.substring(0, dot);
  }

  static String _mimeTypeOf(String path) => switch (extensionOf(path)) {
    'mp3' => 'audio/mpeg',
    'm4a' || 'aac' => 'audio/mp4',
    'wav' => 'audio/wav',
    'ogg' => 'audio/ogg',
    'flac' => 'audio/flac',
    _ => 'audio/*',
  };

  static String _lastLine(String? logs) {
    if (logs == null || logs.trim().isEmpty) return '';
    final List<String> lines = logs
        .trim()
        .split('\n')
        .where((String l) => l.trim().isNotEmpty)
        .toList();
    return lines.isEmpty ? '' : lines.last.trim();
  }
}

/// `m:ss`, or `h:mm:ss` for anything over an hour.
String formatDuration(Duration? value) {
  if (value == null) return '0:00';
  final int total = value.inSeconds < 0 ? 0 : value.inSeconds;
  final String seconds = (total % 60).toString().padLeft(2, '0');
  final int minutes = (total % 3600) ~/ 60;
  final int hours = total ~/ 3600;
  if (hours > 0) {
    return '$hours:${minutes.toString().padLeft(2, '0')}:$seconds';
  }
  return '$minutes:$seconds';
}

/// `4.2 MB`, `812 KB`.
String formatSize(int bytes) {
  if (bytes >= 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
  if (bytes >= 1024) return '${(bytes / 1024).round()} KB';
  return '$bytes B';
}
