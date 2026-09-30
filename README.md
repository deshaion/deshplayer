<img src="icon-source.png" alt="Deshplayer icon" width="160">
# DeshPlayer

## Media Player - Synchronization

Deshplayer seamlessly synchronizes your media and data with cloud storage to provide a unified experience.

- **Metadata Synchronization:** The application relies on a per-folder `metadata.json` stored in the cloud. If a downloaded track is missing artist or duration information, the player extracts embedded tags from the file and triggers an asynchronous cloud update to keep the metadata in sync.
- **Playback Statistics:** Track playback statistics (tracked uniquely by 'Artist - Title') are stored locally and synced to the cloud. This synchronization process utilizes MD5 hashes to optimize updates and minimize unnecessary network traffic.
- **Automatic Track Sync:** Deshplayer automatically detects if a track file is removed from your cloud storage. If a track is deleted from the cloud, the player will seamlessly handle the playback error, automatically remove the track from your local library and all playlists, and skip to the next track.

## Playlists & Book Mode

Deshplayer supports organizing your tracks into custom playlists.

To improve the experience for listening to podcasts or audiobooks, playlists can be toggled into **Book Mode** via the `Manage Playlists` page.

When playing a Book Mode playlist:
- **Sequential Playback:** Tracks are played sequentially, ignoring global shuffle or repeat settings.
- **Isolated Queue:** The active queue for standard playlists is paused and saved in the background. Book mode generates its own isolated playback queue. When you switch back to playing a regular playlist, your original queue is restored seamlessly.
- **Resume Capability:** If you switch to another playlist and return to a Book Mode playlist later, a "Resume" block will appear at the top of the track list (desktop) or below the control panel (mobile). This allows you to restore your exact playback position (including the paused track and time) with a single click.

## How to build it

Before building for any platform, ensure you have Flutter installed and run `flutter doctor` to verify your environment is set up correctly.

The project uses `build_runner` and `hive_generator` to generate Hive type adapters for local storage. Before running or building the app, make sure to generate these files:

```bash
dart run build_runner build --delete-conflicting-outputs
```

### Android

For Android, follow the standard Flutter setup instructions provided by `flutter doctor`. Once your environment is ready, you can build the APK:

```bash
flutter build apk
```

or 
```bash
flutter build apk --target-platform android-arm64
```

### Linux

To build the application for Linux, you need to install several development tools and system dependencies. Run the following commands in your terminal:

```bash
sudo apt update
sudo apt install clang cmake ninja-build libgtk-3-dev
sudo apt install lld-18 llvm-18
sudo apt install libsecret-1-dev
```

On Linux, run the application with `NO_XIPH_LIBS=1` so that
`flutter_soloud` does not link the system Xiph codec libraries:

```bash
NO_XIPH_LIBS=1 flutter run -d linux
```

Use the same environment variable when creating a Linux release build:

```bash
NO_XIPH_LIBS=1 flutter build linux
```

This setting disables SoLoud's Xiph-backed Ogg, Opus, Vorbis, and FLAC
support. MP3 and the other non-Xiph formats supported by SoLoud remain
available. If you change this setting after an earlier Linux build, run
`flutter clean` once before running or rebuilding so CMake regenerates the
native configuration.

#### Troubleshooting: `KeyringLocked` when opening Settings

Deshplayer stores cloud access tokens through `libsecret`. Linux therefore
needs a Secret Service provider such as GNOME Keyring in addition to the
`libsecret` library. If one is not installed, install GNOME Keyring and its
management UI:

```bash
sudo apt install gnome-keyring seahorse
```

If Settings reports `KeyringLocked`, first log out and back in, then retry the
connection check. On desktops such as XFCE, the Secret Service component may
not start automatically. It can be started for the current session with:

```bash
gnome-keyring-daemon --start --components=secrets
```

Use **Passwords and Keys** (`seahorse`) to confirm that the **Passwords** and
**Login** keyrings are visible and unlocked.

If Seahorse instead reports an error similar to the following, the running
daemon has stale in-memory state:

```text
No such secret item at path: /org/freedesktop/secrets/collection/login/11
```

Back up the encrypted keyring, replace the daemon, and reopen Seahorse:

```bash
cp -a ~/.local/share/keyrings \
  ~/.local/share/keyrings.backup-$(date +%Y%m%d-%H%M%S)
export GNOME_KEYRING_CONTROL=/run/user/$(id -u)/keyring
gnome-keyring-daemon --replace --daemonize
pkill seahorse
seahorse
```

Unlock the **Login** keyring if prompted, return to Deshplayer Settings, and
select **Retry**. A normal reboot also restarts the daemon. Do not delete
`~/.local/share/keyrings`; it may contain credentials used by Deshplayer and
other applications.

### macOS

The macOS build uses CocoaPods and CMake to compile the native
`flutter_soloud` audio library. Install CMake before building. With Homebrew:

```bash
brew install cmake
```

Confirm that CMake is available to the build:

```bash
cmake --version
```

The app stores cloud API tokens in the macOS Keychain. Its Keychain Sharing
entitlement requires the Runner to be signed with an Apple Development
certificate; ad-hoc signing is not sufficient. Configure signing in Xcode:

1. Open `macos/Runner.xcworkspace` (not `Runner.xcodeproj`).
2. Select the blue **Runner** project in the Project Navigator (`Command+1`).
3. Under **TARGETS**, select **Runner**, then open **Signing & Capabilities**.
4. Enable **Automatically manage signing** and select your Apple Developer
   team.

During the first signed build, macOS may ask for the password of the `login`
keychain. This is normally your Mac user-account password, not your Apple ID
or cloud API password. If the prompt identifies Xcode or `codesign`, choose
**Always Allow** to avoid approving the certificate key on every build.

After installing CMake or changing package/signing configuration, create a
clean build:

```bash
flutter clean
flutter pub get
flutter build macos
```

*Note: You may encounter errors related to the target OS version during the build process. If this happens, you will need to open the `macos/Runner.xcworkspace` in Xcode and adjust the minimum deployment target.*

## Changing the Version Number Before Building

To change the version number of the application before creating a build, you need to modify the `version` field in the `pubspec.yaml` file located in the root of the project.

The `version` field looks like this:
```yaml
version: 1.0.0+1
```

* **`1.0.0`**: This is the version number. Update this for releases (e.g., `1.0.1` or `1.1.0`).
* **`+1`**: This is the build number. Increment this for every new build you upload to an app store or distribute, even if the version number remains the same.

After updating the `pubspec.yaml`, make sure to run `flutter pub get` before running your build commands (e.g., `flutter build apk`).
