import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// Two daily reminders, scheduled entirely on-device.
///
/// No Firebase, no server, no network — the OS alarm manager holds the
/// schedule, so the reminders keep firing when the app is closed and (thanks to
/// the boot receiver declared in AndroidManifest.xml) after a restart.
class NotificationService {
  NotificationService._();

  static final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  /// Lets a notification tap return to the Home screen even when the app was
  /// already running on a deeper screen. Wired to [MaterialApp.navigatorKey].
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  // Fixed ids. Scheduling with an id that already exists *replaces* it, so
  // reopening the app can never stack up duplicate reminders.
  static const int _morningId = 1001;
  static const int _eveningId = 1002;

  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'slow_vibes_daily',
    'Daily reminders',
    description: 'Gentle nudges to turn a song into Slow + Reverb.',
    importance: Importance.defaultImportance,
  );

  /// Call once from `main()`, before `runApp`.
  static Future<void> init() async {
    _configureTimeZone();

    await _plugin.initialize(
      settings: const InitializationSettings(
        // @mipmap/ic_launcher is the app icon, already present.
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: _onTap,
    );

    final AndroidFlutterLocalNotificationsPlugin? android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();

    // The channel must exist before anything is posted to it; creating it
    // again with the same id is a no-op.
    await android?.createNotificationChannel(_channel);

    // Android 13+ requires an explicit grant. On older versions this resolves
    // immediately as granted. A refusal is not fatal — the schedule is still
    // registered, so enabling notifications later in Settings just works.
    await android?.requestNotificationsPermission();

    await scheduleDailyReminders();
  }

  /// Registers (or re-registers) both daily reminders.
  static Future<void> scheduleDailyReminders() async {
    await _scheduleDaily(
      id: _morningId,
      hour: 10,
      minute: 0,
      title: '🎵 Start Your Vibe',
      body: 'Turn your favorite song into beautiful Slow + Reverb.',
    );

    await _scheduleDaily(
      id: _eveningId,
      hour: 20,
      minute: 0,
      title: '🌙 Evening Vibes',
      body: 'Relax with your favorite Slow + Reverb music.',
    );
  }

  static Future<void> _scheduleDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
  }) async {
    await _plugin.zonedSchedule(
      id: id,
      title: title,
      body: body,
      scheduledDate: _nextInstanceOf(hour, minute),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      // Inexact on purpose. Exact alarms need SCHEDULE_EXACT_ALARM, which
      // Google grants only to alarm/calendar apps — requesting it in a music
      // app is a likely Play Store rejection. The OS may shift these by a few
      // minutes to batch wake-ups, which is fine for a reminder and much
      // kinder to the battery.
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // This is what makes it repeat: match only the time-of-day, so the
      // notification fires again every day at the same clock time.
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  /// The next occurrence of [hour]:[minute], today if it has not passed yet,
  /// otherwise tomorrow.
  static tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    if (!scheduled.isAfter(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }
    return scheduled;
  }

  /// Points `tz.local` at a zone matching the device's current UTC offset.
  ///
  /// `zonedSchedule` needs a real timezone, and the timezone database is keyed
  /// by IANA name ("Asia/Kolkata") — a name Dart cannot report;
  /// `DateTime.now().timeZoneName` gives an abbreviation like "IST" that the
  /// database does not accept. Matching on the current offset avoids pulling in
  /// another package just to read one string.
  ///
  /// Caveat: this picks *a* zone with the right offset, not necessarily the
  /// user's own, so the DST rules may differ. Reminders would then shift by an
  /// hour across a DST change until the app is next opened. Harmless here
  /// (India, the primary audience, has no DST), but if that matters, add the
  /// `flutter_timezone` package and replace this with:
  ///     tz.setLocalLocation(tz.getLocation(await FlutterTimezone.getLocalTimezone()));
  static void _configureTimeZone() {
    tz_data.initializeTimeZones();

    final Duration offset = DateTime.now().timeZoneOffset;
    for (final tz.Location location in tz.timeZoneDatabase.locations.values) {
      if (location.currentTimeZone.offset == offset) {
        tz.setLocalLocation(location);
        return;
      }
    }
    // No match: tz.local stays UTC. Scheduling still works, it is just
    // anchored to UTC rather than local wall-clock.
  }

  /// Brings the user back to the Home screen when a notification is tapped.
  ///
  /// Launching from cold start already lands on Home (it is `MaterialApp.home`),
  /// so this only matters when the app was left open on the Editor or Preview.
  static void _onTap(NotificationResponse response) {
    navigatorKey.currentState?.popUntil(
      (Route<dynamic> route) => route.isFirst,
    );
  }

  /// Removes both reminders. Not wired to any UI — here so a settings toggle
  /// can be added later without touching this file.
  static Future<void> cancelAll() async {
    await _plugin.cancel(id: _morningId);
    await _plugin.cancel(id: _eveningId);
  }

  /// Currently scheduled reminders, for debugging.
  static Future<List<PendingNotificationRequest>> pending() =>
      _plugin.pendingNotificationRequests();
}
