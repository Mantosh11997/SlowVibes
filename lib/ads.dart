import 'dart:async';
import 'dart:io';

import 'package:google_mobile_ads/google_mobile_ads.dart';

/// What happened when we tried to show a rewarded ad.
enum AdOutcome {
  /// The user watched enough of the ad to earn the reward.
  rewarded,

  /// The ad played but the user closed it before the reward point.
  skipped,

  /// No ad could be shown — no network, no fill, or ads are unsupported here.
  unavailable,
}

/// Rewarded ads.
///
/// ## Test IDs are in use
///
/// The unit IDs below are **Google's official test IDs**. They always fill, and
/// they are the only IDs safe to use during development — showing or tapping
/// your own live ads gets an AdMob account suspended. Before publishing:
///
///  1. Create an app + rewarded ad unit in the AdMob console.
///  2. Replace [_androidRewardedUnitId] / [_iosRewardedUnitId] below.
///  3. Replace the `APPLICATION_ID` meta-data in
///     `android/app/src/main/AndroidManifest.xml` with your real AdMob app ID.
///
/// Steps 2 and 3 are separate — the app ID and the ad unit ID are different
/// values, and getting them mixed up produces ads that silently never load.
class Ads {
  Ads._();

  // Google's official test rewarded units.
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

  /// Shows a rewarded ad and resolves once it closes.
  ///
  /// Waits briefly for a preloaded ad if one is still in flight, so a user who
  /// taps Download the instant the screen opens still sees an ad rather than
  /// falling straight through to [AdOutcome.unavailable].
  static Future<AdOutcome> showRewarded() async {
    if (!Platform.isAndroid && !Platform.isIOS) {
      return AdOutcome.unavailable;
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
    // ~3s total. Longer than this and the user is just staring at a spinner
    // for an ad, which is worse than letting the download through.
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
