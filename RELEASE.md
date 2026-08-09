# Release checklist — Play Store + AdMob

Everything needed to take Slow Vibes from this repository to a live listing,
in the order it has to happen. Steps marked **blocking** will get the upload
rejected, or the ads silently unfilled, if skipped.

---

## 1. Signing (blocking)

Play will not accept a debug-signed build. The Gradle script reads
`android/key.properties`, which is git-ignored and must exist on the machine
doing the release build:

```properties
storeFile=/absolute/path/to/slow-vibes-upload.jks
storePassword=…
keyAlias=upload
keyPassword=…
```

If that file is missing the release build silently falls back to the debug key
— see `android/app/build.gradle.kts`. Back up the `.jks` file and its
passwords somewhere durable; losing them means you can never update the app
under the same listing without Google's key-reset process.

Confirm what you actually built:

```
keytool -printcert -jarfile build/app/outputs/bundle/release/app-release.aab
```

The owner must be your upload key, not `CN=Android Debug`.

---

## 2. Build the upload artifact (blocking)

Play takes an **app bundle** (`.aab`), not an APK:

```
flutter clean
flutter pub get
flutter build appbundle --release
```

Output: `build/app/outputs/bundle/release/app-release.aab`.

The APKs produced by CI are for sideloading and testing only.

Version numbers come from `pubspec.yaml` (`version: 1.0.0+1` → versionName
`1.0.0`, versionCode `1`). Every subsequent upload needs a higher build number
after the `+`.

`targetSdk` resolves to 36 through the Flutter Gradle plugin on Flutter
3.44.6, which satisfies Play's current target-API requirement. Re-check this
if the Flutter version in `.github/workflows/build.yml` ever moves backwards.

---

## 3. Verify the live AdMob wiring — without clicking your own ads (blocking)

The IDs in the repo are the production pair and they match:

| Where | Value |
|---|---|
| `android/app/src/main/AndroidManifest.xml` (app ID) | `ca-app-pub-4506957183782274~7716476517` |
| `lib/ads.dart` (rewarded unit ID) | `ca-app-pub-4506957183782274/3204330524` |

Same publisher number, `~` in the app ID, `/` in the unit ID. That is the part
that can be checked by reading; whether the unit actually serves can only be
checked on a device.

**Do not test by watching real ads on your own phone.** Google detects
self-clicks and suspends accounts. Instead:

1. `flutter run` once and find this line in the log:
   `Use RequestConfiguration.Builder().setTestDeviceIds(Arrays.asList("…"))`
2. Paste that hex string into `_testDeviceIds` in `lib/ads.dart`.
3. Run again. The request still goes to the **live** ad unit — proving the app
   ID, the unit ID, the manifest entry and the consent flow are all correct —
   but Google returns a test ad, which is safe to watch and click.
4. **Empty `_testDeviceIds` again before building the upload bundle.** A real
   user left in that list would only ever see test ads and earn nothing.

Expect no fill for the first few hours on a brand-new ad unit. `No ad
available right now` immediately after creating the unit usually means "not
warmed up yet", not "broken".

---

## 4. AdMob console

- **Link the app to its Play listing.** In AdMob → Apps → Slow Vibes → App
  settings, once the app is published. Unlinked apps get restricted ad serving.
- **Configure the GDPR and US-state privacy messages.** AdMob → Privacy &
  messaging. The app calls Google's User Messaging Platform at launch
  (`Ads._gatherConsent`), but the SDK can only show a message that exists in
  the console. Without one configured, EEA/UK/Swiss users are not monetised.
- **`app-ads.txt`** — optional but worth doing; it protects the inventory from
  spoofing and some demand sources require it. It must be served from the root
  of the domain you put in the Play listing's *Website* field:
  `https://<your-domain>/app-ads.txt`. The current privacy-policy URL is a
  GitHub *project* page (`mantosh11997.github.io/SlowVibes/…`), whose root
  domain is `mantosh11997.github.io` — so the file has to go in a
  `mantosh11997.github.io` repository, not this one. AdMob shows the exact
  line to publish under Apps → app-ads.txt.

---

## 5. Play Console — App content (blocking)

These answers must match what the app actually does. Mismatches are the most
common cause of a rejection or a post-launch policy strike.

| Section | Answer |
|---|---|
| Privacy policy | `https://mantosh11997.github.io/SlowVibes/privacy-policy.html` |
| Ads | **Yes, contains ads** |
| Target audience | 13+ — the app is not designed for children |
| Advertising ID | **Yes.** The Google Mobile Ads SDK merges `com.google.android.gms.permission.AD_ID` into the manifest automatically. Purposes: advertising/marketing and fraud prevention |
| Content rating | Answer the questionnaire honestly. `maxAdContentRating` is set to `T` in `lib/ads.dart`; do not let the declared rating come out below what the ads may show |
| Data safety | See below |
| Government app / financial features / health | No |

### Data safety

The app itself collects nothing — no accounts, no analytics, no audio leaves
the device. The AdMob SDK does collect, and that has to be declared as yours:

- **Device or other IDs** → *Collected* and *Shared*, purposes: Advertising or
  marketing, Fraud prevention and security. Not processed ephemerally.
- Answer **No** to everything under Personal info, Financial info, Photos and
  videos, Audio files, Messages and Contacts — the imported song is read
  through the system picker, processed locally and never transmitted.
- Data is encrypted in transit: **Yes** (the SDK's ad requests use HTTPS).

Google publishes the authoritative per-SDK list at
<https://support.google.com/admob/answer/11150250>; check it against the
`google_mobile_ads` version in `pubspec.lock` (currently 9.0.0) before
submitting.

---

## 6. Store listing

Copy lives in `store/listing.md`; graphics in `store/`.

Still missing: **at least two phone screenshots** (1080p or higher). Capture
them from a device with:

```
adb exec-out screencap -p > screenshot-home.png
```

Home, Editor with a song loaded, Processing, Preview and Library are the five
worth having.

---

## 7. Before hitting publish

- [ ] `flutter analyze` and `flutter test` clean
- [ ] `_testDeviceIds` in `lib/ads.dart` is empty
- [ ] AAB is signed with the upload key, not the debug key
- [ ] Installed the release build on a real device and confirmed: a song
      imports, processes, previews, and the Download button plays an ad and
      writes into `Music/Slow Vibes/`
- [ ] Consent form appears when tested with `DebugGeography.debugGeographyEea`
      (temporary `ConsentDebugSettings` in `Ads._gatherConsent`), and the
      *Ad privacy settings* button on Home appears with it
- [ ] Privacy policy URL loads publicly, in an incognito window

Use a **closed test** track first. It exercises the whole upload, signing and
review path without the listing going public, and Play now requires a period
of closed testing for new personal developer accounts before production
access is granted.
