import 'dart:async';
import 'dart:io';

import 'package:google_mobile_ads/google_mobile_ads.dart';

/// What happened when we tried to show a rewarded ad.
enum AdOutcome {
  /// The user watched enough of the ad to earn the reward.
  rewarded,

  /// The ad played but the user closed it before the reward point.
  skipped,

  /// The device is offline, so no ad could be fetched.
  noNetwork,

  /// There is a connection but no ad could be loaded or shown — usually no
  /// fill from the ad network.
  unavailable,
}

/// Rewarded ads.
///
/// ## LIVE IDs are currently in use
///
/// The production AdMob IDs are active in this file and in
/// `android/app/src/main/AndroidManifest.xml`. They are a matched pair: the app
/// ID contains a `~`, the ad unit ID contains a `/`, and both carry the same
/// publisher number (`4506957183782274`). Changing one without the other is the
/// most common cause of a rewarded ad that never appears.
///
/// ## Never tap your own live ads
///
/// Viewing or clicking your own live ads is what gets an AdMob account
/// suspended, and Google detects it. To check the live wiring on your own
/// phone, put your device's ad ID in [_testDeviceIds] below: the request still
/// goes to the live unit — proving the IDs, the manifest and the consent flow
/// are all correct — but Google returns a test ad, which is safe to watch.
///
/// The TEST unit IDs kept commented out below are the other option; they always
/// fill, but they bypass the live unit entirely and so prove nothing about it.
///
/// ## Consent
///
/// [init] runs Google's User Messaging Platform (UMP) flow before starting the
/// ads SDK. In the EEA, the UK and Switzerland this shows the consent message
/// configured in AdMob → Privacy & messaging; everywhere else it is a no-op.
/// Serving ads to those users through a certified consent platform is an AdMob
/// policy requirement, not an optional extra — without it those impressions
/// stop being monetised.
class Ads {
  Ads._();

  // ---------------------------------------------------------------------------
  // LIVE — Slow Vibes production AdMob (ACTIVE)
  // ---------------------------------------------------------------------------
  // Matching app ID lives in AndroidManifest.xml:
  //     ca-app-pub-4506957183782274~7716476517
  static const String _androidRewardedUnitId =
      'ca-app-pub-4506957183782274/3204330524';

  // iOS still points at Google's test unit: no live iOS unit exists. iOS needs
  // its own AdMob *app* entry and its own rewarded unit — the Android IDs will
  // not serve there. Harmless while shipping Android only.
  static const String _iosRewardedUnitId =
      'ca-app-pub-3940256099942544/1712485313';

  // ---------------------------------------------------------------------------
  // TEST — Google's official sample units (uncomment to go back to testing)
  // ---------------------------------------------------------------------------
  // static const String _androidRewardedUnitId =
  //     'ca-app-pub-3940256099942544/5224354917';

  static String get _rewardedUnitId =>
      Platform.isIOS ? _iosRewardedUnitId : _androidRewardedUnitId;

  /// Devices that get a test ad back from the LIVE ad unit above.
  ///
  /// This is the only safe way to confirm the production setup on your own
  /// phone. To find your ID, run the app once with `flutter run` and look for
  /// this line in the logs:
  ///
  ///     Use RequestConfiguration.Builder().setTestDeviceIds(
  ///         Arrays.asList("33BE2250B43518CCDA7DE426D04EE231"))
  ///
  /// Paste that hex string in here. It is per-device and per-install, and it
  /// changes if you reset your advertising ID or reinstall the app.
  ///
  /// Leave the list empty for the build you upload to Play — a real user in
  /// this list would only ever see test ads and would never earn you anything.
  static const List<String> _testDeviceIds = <String>[];

  /// The ad kept ready so the Download button responds instantly instead of
  /// making the user wait for a network round trip after they tap.
  static RewardedAd? _preloaded;
  static bool _loading = false;

  /// Set once [MobileAds.initialize] has run, which only happens after consent
  /// allows ads to be requested at all.
  static bool _sdkStarted = false;

  /// The in-flight (or finished) [init] call, so later callers can wait for the
  /// same startup instead of racing it.
  static Future<bool>? _startup;

  static bool _privacyOptionsRequired = false;

  /// Whether this user must be offered a way to change their ad consent.
  ///
  /// True only where a consent message applies — in the EEA, the UK and
  /// Switzerland. The Home screen uses it to decide whether to show the ad
  /// privacy button; UMP policy requires that entry point to exist wherever the
  /// consent form itself was shown.
  static bool get privacyOptionsRequired => _privacyOptionsRequired;

  /// Called once from `main()`.
  ///
  /// Gathers consent first, then starts the ads SDK if consent allows it.
  /// Nothing here is allowed to throw into the app: a failure just means no ads
  /// this session, never a broken launch.
  static Future<void> init() async {
    _startup ??= _start();
    await _startup;
  }

  static Future<bool> _start() async {
    try {
      await _gatherConsent();
    } catch (_) {
      // A consent failure is not fatal. canRequestAds() below still reports
      // whether ads are allowed — outside the EEA it stays true.
    }
    return _startSdkIfAllowed();
  }

  /// Runs the UMP flow: refresh the user's status, then show the consent form
  /// if one is required and has not been answered yet.
  static Future<void> _gatherConsent() async {
    final Completer<void> updated = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      () {
        if (!updated.isCompleted) updated.complete();
      },
      (FormError error) {
        if (!updated.isCompleted) updated.complete();
      },
    );

    // A device with no network never gets either callback, and the app must not
    // wait on it — the first ad request would fail on connectivity anyway.
    await updated.future.timeout(const Duration(seconds: 10), onTimeout: () {});

    // No-op where no consent message applies, or where the user has already
    // answered one; the SDK caches the decision across sessions.
    await ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {});

    _privacyOptionsRequired =
        await ConsentInformation.instance
            .getPrivacyOptionsRequirementStatus() ==
        PrivacyOptionsRequirementStatus.required;
  }

  /// Starts the ads SDK, but only if consent permits ad requests. Idempotent,
  /// so it is safe to call again after the user changes their choice.
  static Future<bool> _startSdkIfAllowed() async {
    if (_sdkStarted) return true;

    bool allowed;
    try {
      allowed = await ConsentInformation.instance.canRequestAds();
    } catch (_) {
      // UMP unreachable. Outside the EEA consent is not required, so refusing
      // to serve any ad at all would be the worse failure.
      allowed = true;
    }
    if (!allowed) return false;

    _sdkStarted = true;
    try {
      await MobileAds.instance.initialize();
      await MobileAds.instance.updateRequestConfiguration(
        RequestConfiguration(
          // Caps what the network may serve. Keep this in step with the Play
          // Console content rating: 'T' matches a Teen rating, and loosening it
          // to 'MA' would make the app's declared rating wrong.
          maxAdContentRating: MaxAdContentRating.t,
          testDeviceIds: _testDeviceIds,
        ),
      );
    } catch (_) {
      // Ads are never allowed to stop the app from starting.
    }
    return true;
  }

  /// Waits for startup and reports whether an ad may be requested.
  static Future<bool> _ready() async {
    if (_sdkStarted) return true;
    final Future<bool>? startup = _startup;
    if (startup == null) return init().then((_) => _sdkStarted);
    // Bounded: the consent form is modal and the user may sit on it, but the
    // caller cannot hang forever waiting for them.
    return startup.timeout(
      const Duration(seconds: 30),
      onTimeout: () => _sdkStarted,
    );
  }

  /// Re-opens the consent form so the user can change what they agreed to.
  ///
  /// Only meaningful when [privacyOptionsRequired] is true.
  static Future<void> showPrivacyOptions() async {
    await ConsentForm.showPrivacyOptionsForm((FormError? error) {});
    // They may have just granted consent for the first time, which is what
    // allows the SDK to start.
    await _startSdkIfAllowed();
  }

  /// Fetches an ad in the background. Safe to call repeatedly.
  static void preload() {
    if (_preloaded != null || _loading) return;
    _loading = true;
    unawaited(_loadNow());
  }

  static Future<void> _loadNow() async {
    if (!await _ready()) {
      _loading = false;
      return;
    }

    RewardedAd.load(
      adUnitId: _rewardedUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (RewardedAd ad) {
          _preloaded = ad;
          _loading = false;
        },
        onAdFailedToLoad: (LoadAdError error) {
          _preloaded = null;
          _loading = false;
        },
      ),
    );
  }

  /// Whether the device can currently reach the network.
  ///
  /// A DNS lookup rather than a package: it needs no dependency, and resolving
  /// the ad-serving host is a closer proxy for "can we actually fetch an ad"
  /// than a generic connectivity flag, which reports "connected" for a Wi-Fi
  /// network that has no working internet behind it.
  static Future<bool> hasNetwork() async {
    try {
      final List<InternetAddress> result = await InternetAddress.lookup(
        'googleads.g.doubleclick.net',
      ).timeout(const Duration(seconds: 4));
      return result.isNotEmpty && result.first.rawAddress.isNotEmpty;
    } on SocketException {
      return false;
    } on TimeoutException {
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Shows a rewarded ad and resolves once it closes.
  ///
  /// Waits briefly for a preloaded ad if one is still in flight, so a user who
  /// taps Download the instant the screen opens still sees an ad rather than
  /// falling straight through to [AdOutcome.unavailable].
  static Future<AdOutcome> showRewarded() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return AdOutcome.unavailable;
    }

    // Checked up front so an offline user gets "turn on mobile data" straight
    // away instead of waiting out the preload timeout for a generic failure.
    if (!await hasNetwork()) return AdOutcome.noNetwork;

    // Consent gathering and SDK startup happen once, at launch; this only
    // waits if the user tapped Download before it finished. A false here means
    // consent was declined, so no ad request may be made at all.
    if (!await _ready()) return AdOutcome.unavailable;

    RewardedAd? ad = _preloaded;

    if (ad == null) {
      if (!_loading) preload();
      ad = await _waitForPreload();
    }

    if (ad == null) return AdOutcome.unavailable;

    // Consume it; the next one is fetched below so the following download is
    // ready too.
    _preloaded = null;

    final Completer<AdOutcome> completer = Completer<AdOutcome>();
    var earned = false;

    ad.fullScreenContentCallback = FullScreenContentCallback<RewardedAd>(
      onAdDismissedFullScreenContent: (RewardedAd ad) {
        ad.dispose();
        if (!completer.isCompleted) {
          completer.complete(earned ? AdOutcome.rewarded : AdOutcome.skipped);
        }
        preload();
      },
      onAdFailedToShowFullScreenContent: (RewardedAd ad, AdError error) {
        ad.dispose();
        if (!completer.isCompleted) completer.complete(AdOutcome.unavailable);
        preload();
      },
    );

    try {
      await ad.show(
        onUserEarnedReward: (AdWithoutView ad, RewardItem reward) {
          earned = true;
        },
      );
    } catch (_) {
      if (!completer.isCompleted) completer.complete(AdOutcome.unavailable);
    }

    return completer.future;
  }

  /// Polls briefly for an in-flight preload.
  static Future<RewardedAd?> _waitForPreload() async {
    const Duration step = Duration(milliseconds: 150);
    // ~3s total. We already know the device is online by this point, so this
    // only covers a slow fetch; beyond a few seconds it is better to report
    // "no ad available" than to leave the user watching a spinner.
    for (var i = 0; i < 20; i++) {
      if (_preloaded != null) return _preloaded;
      if (!_loading) break; // Load already failed.
      await Future<void>.delayed(step);
    }
    return _preloaded;
  }

  /// Releases any ad held in memory.
  static void dispose() {
    _preloaded?.dispose();
    _preloaded = null;
  }
}
