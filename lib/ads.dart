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
/// ## TEST IDs are currently in use
///
/// The live AdMob IDs are recorded below but commented out. Test IDs always
/// fill and are the only IDs safe to use during development — viewing or
/// tapping your own live ads is what gets an AdMob account suspended, and
/// Google detects it.
///
/// ## Release checklist — BOTH steps, or ads silently never load
///
///  1. In this file: comment out the TEST block, uncomment the LIVE block.
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
  // LIVE — Slow Vibes production AdMob (uncomment for release)
  // ---------------------------------------------------------------------------
  // App ID (goes in AndroidManifest.xml, not here):
  //     ca-app-pub-4506957183782274~7716476517
  //
  // static const String _androidRewardedUnitId =
  //     'ca-app-pub-4506957183782274/3204330524';
  //
  // NOTE: there is no live iOS unit yet. iOS needs its own AdMob *app* entry
  // and its own rewarded unit — the Android IDs will not serve on iOS.
  // static const String _iosRewardedUnitId = 'ca-app-pub-XXXXXXXX/XXXXXXXX';

  // ---------------------------------------------------------------------------
  // TEST — Google's official sample units (in use)
  // ---------------------------------------------------------------------------
  static const String _androidRewardedUnitId =
      'ca-app-pub-3940256099942544/5224354917';
  static const String _iosRewardedUnitId =
      'ca-app-pub-3940256099942544/1712485313';

  static String get _rewardedUnitId =>
      Platform.isIOS ? _iosRewardedUnitId : _androidRewardedUnitId;

  static bool _initialised = false;

  /// The ad kept ready so the Download button responds instantly instead of
  /// making the user wait for a network round trip after they tap.
  static RewardedAd? _preloaded;
  static bool _loading = false;

  /// Called once from `main()`.
  static Future<void> init() async {
    if (_initialised) return;
    _initialised = true;
    try {
      await MobileAds.instance.initialize();
    } catch (_) {
      // Ads are never allowed to stop the app from starting.
    }
  }

  /// Fetches an ad in the background. Safe to call repeatedly.
  static void preload() {
    if (_preloaded != null || _loading) return;
    _loading = true;

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
