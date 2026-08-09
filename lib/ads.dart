import 'dart:async';
import 'dart:io';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_test_config.dart';
import 'consent.dart';

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

  /// The user is in a region where consent is required and has not given it,
  /// so no ad may legally be requested. Only reachable in the EEA, the UK and
  /// certain US states.
  consentRequired,
}

/// Rewarded ads.
///
/// ## Consent comes first
///
/// [init] runs the UMP consent flow (see consent.dart) before initialising the
/// SDK, and nothing here requests an ad until that has finished. In a regulated
/// region a user who never completes the form gets [AdOutcome.consentRequired]
/// rather than an ad.
///
/// ## LIVE IDs are currently in use
///
/// Do not view or tap these ads on your own device. Google detects self-clicks
/// and suspends accounts for them; to test on real hardware, register the
/// device as an AdMob test device rather than switching the IDs back.
///
/// ## Switching between LIVE and TEST — BOTH steps, or ads silently never load
///
///  1. In this file: swap the active `_androidRewardedUnitId`.
///  2. In `android/app/src/main/AndroidManifest.xml`: do the same swap for the
///     `com.google.android.gms.ads.APPLICATION_ID` meta-data.
///
/// The app ID and the ad unit ID are different values — the app ID contains a
/// `~`, the ad unit ID contains a `/`. Swapping one and not the other, or
/// putting one where the other belongs, is the most common cause of a rewarded
/// ad that never appears.
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

  static bool _initialised = false;

  /// Completes when the startup sequence — consent, then SDK init — has
  /// finished, however it turned out.
  ///
  /// Everything that touches an ad waits on this. Without it, a user who taps
  /// Download in the first second would race the consent lookup and fall
  /// through to "no ad available" for no reason.
  static final Completer<void> _startup = Completer<void>();

  /// Whether consent permits requesting ads at all. Re-evaluated if the user
  /// completes the form later, so it is not final.
  static bool _adsAllowed = false;

  /// Guards against initialising the SDK twice when consent arrives late.
  static bool _sdkInitialised = false;

  /// The ad kept ready so the Download button responds instantly instead of
  /// making the user wait for a network round trip after they tap.
  static RewardedAd? _preloaded;
  static bool _loading = false;

  /// Called once from `main()`.
  ///
  /// Consent runs *before* `MobileAds.initialize()` — that ordering is the
  /// whole point. Initialising the SDK first can fire off an ad request before
  /// the user has been asked anything, which is exactly the policy breach the
  /// consent form exists to prevent.
  static Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    try {
      _adsAllowed = await Consent.gather();
      if (_adsAllowed) await _initSdk();
    } catch (_) {
      // Ads are never allowed to stop the app from starting.
    } finally {
      if (!_startup.isCompleted) _startup.complete();
    }
  }

  static Future<void> _initSdk() async {
    if (_sdkInitialised) return;
    _sdkInitialised = true;
    try {
      // Registered before initialize() so the very first request is already
      // covered — a test device that is only registered afterwards can still
      // put one real impression on the live account.
      if (kAdTestMode && kAdTestDeviceIds.isNotEmpty) {
        await MobileAds.instance.updateRequestConfiguration(
          RequestConfiguration(testDeviceIds: kAdTestDeviceIds),
        );
      }
      await MobileAds.instance.initialize();
    } catch (_) {
      // Same rule: never fatal.
    }
  }

  /// Fetches an ad in the background. Safe to call repeatedly.
  static void preload() {
    if (_preloaded != null || _loading) return;
    // Claimed up front so two rapid calls cannot both start a load while the
    // first is still waiting on [_startup].
    _loading = true;
    unawaited(_preloadWhenReady());
  }

  static Future<void> _preloadWhenReady() async {
    await _startup.future;

    // Nothing may be requested until consent allows it. The Download button
    // handles this case by offering the form again; here we just stop.
    if (!_adsAllowed) {
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
    // It also has to come before the consent retry below, which needs the
    // network just as much as an ad request does.
    if (!await hasNetwork()) return AdOutcome.noNetwork;

    // Let the startup consent flow finish rather than racing it. Kicked off
    // here too, so a missed init() in main() degrades to a slow first tap
    // instead of a future that never completes.
    if (!_initialised) unawaited(init());
    await _startup.future;

    if (!_adsAllowed) {
      // The user dismissed the form without answering, or it failed to load.
      // Offer it once more instead of leaving Download permanently dead.
      _adsAllowed = await Consent.retry();
      if (!_adsAllowed) return AdOutcome.consentRequired;
      await _initSdk();
    }

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
