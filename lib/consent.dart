import 'dart:async';

import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_test_config.dart';

/// Google's User Messaging Platform (UMP) consent flow.
///
/// AdMob policy requires a certified consent mechanism before ads are served
/// to users in the EEA, the UK, and a growing list of regulated US states.
/// UMP ships inside `google_mobile_ads`, so this needs no extra dependency —
/// but it does have to be *run*, and run before `MobileAds.initialize()`.
///
/// Outside a regulated region the whole flow is a no-op: `requestConsentInfoUpdate`
/// comes back with `ConsentStatus.notRequired`, no form is shown, and
/// [canRequestAds] is true. Nobody in India (the primary audience) ever sees a
/// dialog.
class Consent {
  Consent._();

  /// Runs the startup consent flow and reports whether ads may be requested.
  ///
  /// Three steps, in the order Google's own sample uses:
  ///
  ///  1. Ask UMP whether this user, in this region, needs to be asked anything.
  ///  2. Show the form if — and only if — the answer is yes.
  ///  3. Report back whether ads are now permitted.
  ///
  /// Every failure path resolves rather than throws. A consent lookup that dies
  /// on a flaky network must not take the app's startup down with it, and it
  /// must not silently turn ads on either: on error UMP's cached answer from
  /// the previous session is used, which is `false` on a first run and the
  /// user's real answer on every run after that.
  static Future<bool> gather() async {
    try {
      await _requestUpdate();
      await _showFormIfRequired();
    } catch (_) {
      // Fall through to the status check — UMP keeps the last known good
      // answer, so a failed refresh is not the same as "no consent".
    }
    return canRequestAds();
  }

  /// Whether ads may currently be requested.
  ///
  /// False means the user is in a regulated region and has not completed the
  /// form. Requesting an ad anyway is the policy violation this whole file
  /// exists to prevent.
  static Future<bool> canRequestAds() async {
    try {
      return await ConsentInformation.instance.canRequestAds();
    } catch (_) {
      return false;
    }
  }

  /// Re-runs the form for a user who has not completed it.
  ///
  /// Reached from the Download button when [canRequestAds] is false — someone
  /// who swiped the startup form away would otherwise be left with a button
  /// that can never work and no way to discover why.
  static Future<bool> retry() async {
    try {
      await _requestUpdate();
      await _showFormIfRequired();
    } catch (_) {
      // Same reasoning as gather().
    }
    return canRequestAds();
  }

  /// Whether a "Privacy options" entry point must be offered in the UI.
  ///
  /// True only for users who were shown a form that includes a re-consent
  /// option. UMP policy requires the app to expose a way back to it; see
  /// [showPrivacyOptions].
  static Future<bool> privacyOptionsRequired() async {
    try {
      final PrivacyOptionsRequirementStatus status = await ConsentInformation
          .instance
          .getPrivacyOptionsRequirementStatus();
      return status == PrivacyOptionsRequirementStatus.required;
    } catch (_) {
      return false;
    }
  }

  /// Reopens the consent form so the user can change their earlier answer.
  static Future<void> showPrivacyOptions() async {
    final Completer<void> done = Completer<void>();
    try {
      await ConsentForm.showPrivacyOptionsForm((FormError? error) {
        if (!done.isCompleted) done.complete();
      });
    } catch (_) {
      if (!done.isCompleted) done.complete();
    }
    return done.future;
  }

  // ---------------------------------------------------------------------------
  // Internals
  // ---------------------------------------------------------------------------

  /// Makes UMP treat a listed test device as though it were in the EEA.
  ///
  /// Without this the consent code cannot be tested from India at all: UMP
  /// correctly reports `notRequired`, no form is shown, and a passing run
  /// proves nothing. Returns null in any normal build, which is what makes
  /// real users' regions decide their own behaviour.
  static ConsentDebugSettings? _debugSettings() {
    if (!kAdTestMode || kAdTestDeviceIds.isEmpty) return null;
    return ConsentDebugSettings(
      debugGeography: DebugGeography.debugGeographyEea,
      testIdentifiers: kAdTestDeviceIds,
    );
  }

  /// Bridges UMP's callback-style refresh to a Future.
  ///
  /// Timed out because this is on the startup path: `requestConsentInfoUpdate`
  /// talks to Google's servers, and on a connection that accepts the socket but
  /// never answers, neither callback ever fires. Without the timeout the
  /// Download button would wait forever on a future that cannot complete.
  static Future<void> _requestUpdate() {
    final Completer<void> done = Completer<void>();

    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(consentDebugSettings: _debugSettings()),
      () {
        if (!done.isCompleted) done.complete();
      },
      (FormError error) {
        // A failed refresh is not fatal; the cached status still applies.
        if (!done.isCompleted) done.complete();
      },
    );

    return done.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () {},
    );
  }

  /// Shows the consent form when UMP says one is required, and does nothing at
  /// all otherwise.
  ///
  /// Not timed out, unlike [_requestUpdate]: this future only completes when the
  /// user dismisses the form, and how long they take to read it is their
  /// business.
  static Future<void> _showFormIfRequired() {
    final Completer<void> done = Completer<void>();

    unawaited(
      ConsentForm.loadAndShowConsentFormIfRequired((FormError? error) {
        if (!done.isCompleted) done.complete();
      }).catchError((Object _) {
        if (!done.isCompleted) done.complete();
      }),
    );

    return done.future;
  }
}
