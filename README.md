# deshplayer-private

## Changing the Version Number Before Building

To change the version number of the application before creating a build, you need to modify the `version` field in the `pubspec.yaml` file located in the root of the project.

The `version` field looks like this:
```yaml
version: 1.0.0+1
```

* **`1.0.0`**: This is the version number. Update this for releases (e.g., `1.0.1` or `1.1.0`).
* **`+1`**: This is the build number. Increment this for every new build you upload to an app store or distribute, even if the version number remains the same.

After updating the `pubspec.yaml`, make sure to run `flutter pub get` before running your build commands (e.g., `flutter build apk`).