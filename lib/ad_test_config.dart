/// Compile-time switches for testing ads without touching the live account.
///
/// ## Why compile-time and not `kDebugMode`
///
/// Ad and consent behaviour can only be validated in a *release* build — R8 is
/// on, the ProGuard rules apply, and that is the binary Play receives.
/// `kDebugMode` is false there, so it cannot gate any of this. These flags come
/// from `--dart-define` instead, which works in release builds and defaults to
/// off when the flag is not passed.
///
/// ## Testing
///
///     flutter build apk --release \
///       --dart-define=AD_TEST_MODE=true \
///       --dart-define=AD_TEST_DEVICES=<your-device-hash>
///
/// ## Shipping
///
///     flutter build appbundle --release
///
/// No flags, so [kAdTestMode] is a `const false`. Dart's tree shaker drops
/// every block guarded by it, and [kAdTestDeviceIds] is empty — the device hash
/// is not merely inactive in the shipped binary, it is not present in it.
///
/// ## Finding your device hash
///
/// Install a build, open the app, then:
///
///     adb logcat -d | grep -i "setTestDeviceIds"
///
/// The Google Mobile Ads SDK logs the hash on the first ad request. The same
/// value works for both [kAdTestDeviceIds] and UMP's debug settings.
library;

/// Whether to serve test ads and force the consent form to appear.
///
/// **Never pass this for a Play build.** Test ads earn nothing, and a release
/// serving them would be a live app with no revenue.
const bool kAdTestMode = bool.fromEnvironment('AD_TEST_MODE');

const String _rawTestDevices = String.fromEnvironment('AD_TEST_DEVICES');

/// Devices that should receive test ads, from `--dart-define=AD_TEST_DEVICES`.
///
/// Comma-separated, so several test handsets can be listed at once. Empty in
/// any build that did not pass the flag.
List<String> get kAdTestDeviceIds {
  if (_rawTestDevices.isEmpty) return const <String>[];
  return _rawTestDevices
      .split(',')
      .map((String id) => id.trim())
      .where((String id) => id.isNotEmpty)
      .toList();
}
