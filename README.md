# deshplayer-private

## Media Player - Synchronization

Deshplayer seamlessly synchronizes your media and data with cloud storage to provide a unified experience.

- **Metadata Synchronization:** The application relies on a per-folder `metadata.json` stored in the cloud. If a downloaded track is missing artist or duration information, the player extracts embedded tags from the file and triggers an asynchronous cloud update to keep the metadata in sync.
- **Playback Statistics:** Track playback statistics (tracked uniquely by 'Artist - Title') are stored locally and synced to the cloud. This synchronization process utilizes MD5 hashes to optimize updates and minimize unnecessary network traffic.
- **Automatic Track Sync:** Deshplayer automatically detects if a track file is removed from your cloud storage. If a track is deleted from the cloud, the player will seamlessly handle the playback error, automatically remove the track from your local library and all playlists, and skip to the next track.

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

After installing the dependencies, you can build the Linux application:

```bash
flutter build linux
```

### macOS

For macOS, you can build the application using the standard Flutter command.

*Note: You may encounter errors related to the target OS version during the build process. If this happens, you will need to open the `macos/Runner.xcworkspace` in Xcode and adjust the minimum deployment target.*

```bash
flutter build macos
```

## Changing the Version Number Before Building

To change the version number of the application before creating a build, you need to modify the `version` field in the `pubspec.yaml` file located in the root of the project.

The `version` field looks like this:
```yaml
version: 1.0.0+1
```

* **`1.0.0`**: This is the version number. Update this for releases (e.g., `1.0.1` or `1.1.0`).
* **`+1`**: This is the build number. Increment this for every new build you upload to an app store or distribute, even if the version number remains the same.

After updating the `pubspec.yaml`, make sure to run `flutter pub get` before running your build commands (e.g., `flutter build apk`).
