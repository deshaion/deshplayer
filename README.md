# deshplayer-private

## Media Player - Synchronization

Deshplayer seamlessly synchronizes your media and data with cloud storage to provide a unified experience.

- **Metadata Synchronization:** The application relies on a per-folder `metadata.json` stored in the cloud. If a downloaded track is missing artist or duration information, the player extracts embedded tags from the file and triggers an asynchronous cloud update to keep the metadata in sync.
- **Playback Statistics:** Track playback statistics (tracked uniquely by 'Artist - Title') are stored locally and synced to the cloud. This synchronization process utilizes MD5 hashes to optimize updates and minimize unnecessary network traffic.

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
