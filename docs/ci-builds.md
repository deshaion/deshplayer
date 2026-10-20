# GitHub Actions builds

The **Build applications** workflow runs only on pushed version tags starting
with `v`, published GitHub releases, and manually from **Actions → Build
applications → Run workflow**. Pull requests and branch pushes do not trigger
builds. Push these files to GitHub to enable it. No signing secrets are required
for the initial builds.

Each platform runs independently. Open a completed run and download its
**Artifacts**; they are retained for 14 days. For a published GitHub release,
the workflow also attaches all four files to that release after all platform
builds succeed. It does not upload to app stores.

## Create a release with downloadable builds

1. Update `version:` in `pubspec.yaml` if this is a new app version. Commit and
   push the application changes, workflow, scripts, and `pubspec.lock` first.
2. On GitHub, open **Releases → Draft a new release**.
3. Choose an existing tag containing the workflow, or create a new tag such as
   `v1.1.8` targeting the commit you just pushed. Enter a title and release notes.
4. Click **Publish release**. Publishing a prerelease works too. Saving only a
   draft does not start the build.
5. Open **Actions → Build applications** to watch progress. When all four
   builds succeed, **Attach builds to release** uploads the AppImage, APK, and
   Windows/macOS ZIP files to the release's **Assets** section.

You do not need to run the workflow manually for this path. The release is
visible while its builds run, and the files appear afterward. If a build fails,
the attachment job is skipped; fix the issue and use a new version/tag when the
source needs changes. For a transient failure, rerun the failed jobs from the
Actions run. Rerunning the attachment job replaces existing assets with the same
names. The built-in GitHub token handles uploads; no personal access token is
needed.

Manual workflow runs and matching tag pushes produce Actions artifacts
only. They do not create a GitHub release or attach to an existing one. For an
existing release published before this workflow was installed, you can download
the Actions artifacts and attach their contained files in **Edit release**, or
create a new release using the steps above.

| Artifact | Contents |
| --- | --- |
| `Deshplayer-linux` | `Deshplayer-x86_64.AppImage` |
| `Deshplayer-windows` | ZIP with the x64 executable, DLLs, and assets |
| `Deshplayer-android` | Universal release APK |
| `Deshplayer-macos` | ZIP containing the app, labelled with its architecture and signing mode |

Extract the entire Windows ZIP before launching the executable. For Linux,
make the downloaded AppImage executable (`chmod +x Deshplayer-x86_64.AppImage`).
The Linux build uses Ubuntu 24.04 as its baseline and `NO_XIPH_LIBS=1`, with the
codec limitations described in the main README. It still needs a working
desktop session and Secret Service provider such as GNOME Keyring for cloud
credential storage. An AppImage does not supply the user's keyring service.

The macOS job uses the architecture of the `macos-15` runner (currently Apple
Silicon). It does not produce an Intel or universal build. The project currently
requires macOS 14.5 or later.

Flutter is pinned in `.github/workflows/build.yml`. Commit `pubspec.lock` with
the workflow: CI uses `flutter pub get --enforce-lockfile`. Native build output
is not cached, avoiding stale plugin classes after dependency updates.

## Android signing

Your local release build already uses Android's **debug signing key** through
`android/app/build.gradle.kts`. That is why it installs without configuring a
release certificate. CI keeps this fallback when no signing secrets are set.
These are release-mode APKs signed with a debug key, not unsigned APKs.

GitHub runners are temporary, so their generated debug keys can differ between
runs. Android cannot install an update over an existing app signed with a
different key. Uninstalling first also removes the app's local data. Use a
stable keystore if you want to keep installing updates.

To keep compatibility with the APKs you currently build locally, use your
existing `~/.android/debug.keystore` as the CI keystore. The default alias is
`androiddebugkey`; the default store and key passwords are both `android`.
Verify those values if your environment customized them. Keep a backup of the
keystore. This preserves your current debug signing identity but is not a
production signing setup.

For a new production identity, create a dedicated keystore instead:

```bash
keytool -genkeypair -v -keystore ~/deshplayer-release.jks \
  -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 -alias deshplayer
```

Keep that file and its passwords backed up privately. Do not commit the key.
Switching from your current debug key to this new key requires reinstalling the
app on devices that already have the debug-signed version.

In **Settings → Secrets and variables → Actions → New repository secret**, add
all four secrets:

| Secret | Value |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | Base64-encoded contents of your chosen keystore |
| `ANDROID_STORE_PASSWORD` | Keystore password |
| `ANDROID_KEY_PASSWORD` | Key password |
| `ANDROID_KEY_ALIAS` | Key alias |

On Linux, encode the file with `base64 -w 0 /path/to/keystore.jks`. On macOS use
`base64 -i /path/to/keystore.jks | pbcopy`. Treat this encoded text as a secret.

The workflow creates an ignored `android/key.properties`, signs with the
configured keystore, and removes temporary signing files afterward. Partial
configuration fails rather than silently signing with another key. Pull
requests always use a temporary debug key.

For local builds with the same dedicated key, create `android/key.properties`:

```properties
storeFile=/absolute/path/to/deshplayer-release.jks
storePassword=your-store-password
keyPassword=your-key-password
keyAlias=deshplayer
```

See [Flutter's Android signing guide](https://docs.flutter.dev/deployment/android#sign-the-app)
for Play Store signing and upload keys. This workflow produces APKs for direct
installation, not Play Store app bundles.

## macOS signing and Keychain

With no secrets, CI creates an **ad-hoc signed** app. That lets the workflow
compile and package it without an Apple account. This build is for testing:
the app's Keychain-backed cloud credential storage is unavailable, and macOS
Gatekeeper may block opening it. A successful CI build does not validate
Keychain functionality.

For your own Mac, the easiest first step is to sign locally:

1. Open `macos/Runner.xcworkspace` in Xcode after running `flutter pub get`
   and preparing the CocoaPods project with `flutter build macos --config-only`.
2. In **Xcode → Settings → Accounts**, add your Apple ID.
3. Select the **Runner** target, then **Signing & Capabilities**. Enable
   **Automatically manage signing**, select your team, and add **Keychain
   Sharing**. Use the same team and bundle identifier for subsequent builds.
4. Build and run on your Mac to verify saving and reading cloud credentials.

For downloadable builds on other Macs, use an Apple Developer Program account
and a **Developer ID Application** certificate. A local Apple Development
certificate and development profile are intended for registered test devices;
they are not general distribution credentials.

To enable signed CI builds:

1. Create a Developer ID Application certificate through Xcode or your Apple
   Developer account. In **Keychain Access → My Certificates**, export the
   certificate **with its private key** as a password-protected `.p12` file.
2. In the Apple Developer portal, register an explicit App ID matching
   `PRODUCT_BUNDLE_IDENTIFIER` in `macos/Runner/Configs/AppInfo.xcconfig`
   (currently `com.example.deshplayer`). For distribution, choose an identifier
   you control and update the project consistently before creating the profile.
3. Create/download a matching **macOS Developer ID provisioning profile** for
   that App ID and certificate, authorizing the app's Keychain access group.
   This is a `.provisionprofile` file. The CI script checks the App ID, Keychain
   authorization, and expiration before signing.
4. Add these four repository secrets:

| Secret | Value |
| --- | --- |
| `MACOS_CERTIFICATE_BASE64` | Base64 of the `.p12` certificate and private key |
| `MACOS_CERTIFICATE_PASSWORD` | Password chosen when exporting the `.p12` |
| `MACOS_PROFILE_BASE64` | Base64 of the `.provisionprofile` |
| `MACOS_SIGNING_IDENTITY` | Full identity, e.g. `Developer ID Application: Your Name (TEAMID)` |

On your Mac, use `security find-identity -v -p codesigning` to find the identity
name. Use `base64 -i /path/to/file | pbcopy` to encode each file. Never commit
these files or paste their contents into workflow source.

CI imports the certificate into a temporary keychain, embeds the profile,
configures the app's Keychain group from the profile, signs native libraries,
frameworks, and the app, verifies signatures, and deletes the temporary
keychain. Signing secrets are not used on pull requests. Test a downloaded
signed build on a Mac to verify Keychain access end to end.

Certificate signing and **notarization** are separate. This workflow does not
notarize; signed builds may still trigger Gatekeeper checks. For normal public
distribution, add Apple notarization and stapling once your Developer ID setup
works. See [Apple's Developer ID guidance](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/)
and [GitHub's certificate setup guide](https://docs.github.com/en/actions/how-tos/deploy/deploy-to-third-party-platforms/sign-xcode-applications).
