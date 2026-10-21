#!/usr/bin/env bash
set -euo pipefail

: "${RUNNER_TEMP:?This script runs on a macOS GitHub Actions runner}"
signing_dir="$(mktemp -d "$RUNNER_TEMP/deshplayer-signing.XXXXXX")"
keychain="$signing_dir/signing.keychain-db"
cleanup() {
  if [[ -f "$keychain" ]]; then
    security delete-keychain "$keychain"
  fi
  rm -rf "$signing_dir"
}
trap cleanup EXIT

# Build without requiring a developer account. Signing happens below, after
# Flutter and CocoaPods finish, so pod targets never receive app entitlements.
cat > "$signing_dir/unsigned.xcconfig" <<'CONFIG'
CODE_SIGNING_ALLOWED = NO
CODE_SIGNING_REQUIRED = NO
CODE_SIGN_IDENTITY =
CONFIG
export XCODE_XCCONFIG_FILE="$signing_dir/unsigned.xcconfig"
flutter build macos --release --no-pub
unset XCODE_XCCONFIG_FILE

app="build/macos/Build/Products/Release/deshplayer.app"
test -d "$app"
mkdir -p dist

if [[ -z "${MACOS_CERTIFICATE_BASE64:-}${MACOS_CERTIFICATE_PASSWORD:-}${MACOS_PROFILE_BASE64:-}${MACOS_SIGNING_IDENTITY:-}" ]]; then
  codesign --force --deep --sign - --entitlements macos/Runner/Release.entitlements "$app"
  archive="Deshplayer-macos-$(uname -m)-adhoc.zip"
  echo 'macOS: ad-hoc build; cloud credential storage through Keychain is unavailable. Configure the four MACOS signing secrets for Keychain support.' >> "$GITHUB_STEP_SUMMARY"
else
  : "${MACOS_CERTIFICATE_BASE64:?Set all four MACOS signing secrets}"
  : "${MACOS_CERTIFICATE_PASSWORD:?Set all four MACOS signing secrets}"
  : "${MACOS_PROFILE_BASE64:?Set all four MACOS signing secrets}"
  : "${MACOS_SIGNING_IDENTITY:?Set all four MACOS signing secrets}"
  export SIGNING_DIR="$signing_dir"
  python3 - <<'PY'
import base64
import os
from pathlib import Path

directory = Path(os.environ['SIGNING_DIR'])
for secret, filename in [('MACOS_CERTIFICATE_BASE64', 'certificate.p12'),
                         ('MACOS_PROFILE_BASE64', 'profile.provisionprofile')]:
    data = ''.join(os.environ[secret].split())
    (directory / filename).write_bytes(base64.b64decode(data, validate=True))
PY
  keychain_password="$(openssl rand -hex 32)"
  security create-keychain -p "$keychain_password" "$keychain"
  security set-keychain-settings -lut 21600 "$keychain"
  security unlock-keychain -p "$keychain_password" "$keychain"
  security import "$signing_dir/certificate.p12" -k "$keychain" \
    -P "$MACOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
  security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -s -k "$keychain_password" "$keychain" > /dev/null
  security cms -D -i "$signing_dir/profile.provisionprofile" > "$signing_dir/profile.plist"
  export MACOS_APP_PATH="$app"
  python3 - <<'PY'
import datetime
import fnmatch
import os
import plistlib
from pathlib import Path

directory = Path(os.environ['SIGNING_DIR'])
profile = plistlib.loads((directory / 'profile.plist').read_bytes())
if profile['ExpirationDate'] <= datetime.datetime.now(datetime.timezone.utc).replace(tzinfo=None):
    raise SystemExit('The macOS provisioning profile has expired.')
app = Path(os.environ['MACOS_APP_PATH'])
info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
bundle_id = info['CFBundleIdentifier']
allowed = profile['Entitlements']
app_id = profile['ApplicationIdentifierPrefix'][0] + '.' + bundle_id
if not fnmatch.fnmatchcase(app_id, allowed.get('com.apple.application-identifier', '')):
    raise SystemExit('The macOS profile does not match the app bundle identifier.')
if not any(fnmatch.fnmatchcase(app_id, group) for group in allowed.get('keychain-access-groups', [])):
    raise SystemExit('The macOS profile does not authorize this app Keychain group.')
entitlements = plistlib.loads(Path('macos/Runner/Release.entitlements').read_bytes())
entitlements['com.apple.application-identifier'] = app_id
entitlements['com.apple.developer.team-identifier'] = profile['TeamIdentifier'][0]
entitlements['keychain-access-groups'] = [app_id]
(directory / 'app.entitlements').write_bytes(plistlib.dumps(entitlements))
PY
  cp "$signing_dir/profile.provisionprofile" "$app/Contents/embedded.provisionprofile"
  # Sign nested native code before signing its containing frameworks and app.
  while IFS= read -r -d '' library; do
    codesign --force --timestamp --options runtime --keychain "$keychain" \
      --sign "$MACOS_SIGNING_IDENTITY" "$library"
  done < <(find "$app/Contents" -type f \( -name '*.dylib' -o -name '*.so' \) -print0)
  while IFS= read -r -d '' framework; do
    codesign --force --timestamp --options runtime --keychain "$keychain" \
      --sign "$MACOS_SIGNING_IDENTITY" "$framework"
  done < <(find "$app/Contents" -depth -type d -name '*.framework' -print0)
  codesign --force --timestamp --options runtime --keychain "$keychain" \
    --sign "$MACOS_SIGNING_IDENTITY" --entitlements "$signing_dir/app.entitlements" "$app"
  archive="Deshplayer-macos-$(uname -m)-signed.zip"
  echo 'macOS: certificate-signed with a provisioned Keychain group; not notarized.' >> "$GITHUB_STEP_SUMMARY"
fi
codesign --verify --deep --strict "$app"
ditto -c -k --sequesterRsrc --keepParent "$app" "dist/$archive"
