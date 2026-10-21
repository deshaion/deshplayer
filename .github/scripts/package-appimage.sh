#!/usr/bin/env bash
set -euo pipefail

bundle="${1:-build/linux/x64/release/bundle}"
test -x "$bundle/deshplayer"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
app_dir="$work_dir/Deshplayer.AppDir"
mkdir -p "$app_dir/usr/bin" dist
cp -a "$bundle/." "$app_dir/usr/bin/"

cat > "$work_dir/deshplayer.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Deshplayer
Comment=Media player with cloud synchronization
Exec=deshplayer
Icon=deshplayer
Terminal=false
Categories=AudioVideo;Player;
DESKTOP
cp macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_256.png "$work_dir/deshplayer.png"

curl --fail --location --retry 3 \
  https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-x86_64.AppImage \
  -o "$work_dir/linuxdeploy.AppImage"
curl --fail --location --retry 3 \
  https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh \
  -o "$work_dir/linuxdeploy-plugin-gtk.sh"
chmod +x "$work_dir/linuxdeploy.AppImage" "$work_dir/linuxdeploy-plugin-gtk.sh"

# Native Dart assets may be loaded with dlopen rather than linked from the
# executable. Include each library explicitly so its dependencies are bundled.
libraries=()
while IFS= read -r -d '' library; do
  libraries+=(--library "$library")
done < <(find "$app_dir/usr/bin/lib" -type f -name '*.so*' -print0)

# Extraction mode works on hosted runners without requiring FUSE mounts.
export APPIMAGE_EXTRACT_AND_RUN=1
export DEPLOY_GTK_VERSION=3
export NO_STRIP=1
export OUTPUT="$PWD/dist/Deshplayer-x86_64.AppImage"
export PATH="$work_dir:$PATH"
"$work_dir/linuxdeploy.AppImage" \
  --appdir "$app_dir" \
  --executable "$app_dir/usr/bin/deshplayer" \
  --desktop-file "$work_dir/deshplayer.desktop" \
  --icon-file "$work_dir/deshplayer.png" \
  "${libraries[@]}" \
  --plugin gtk --output appimage
test -s "$OUTPUT"
chmod +x "$OUTPUT"
