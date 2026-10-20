"""Create Gradle signing configuration from optional GitHub Actions secrets."""

import base64
import os
from pathlib import Path


def property_value(value: str) -> str:
    # java.util.Properties treats backslashes, line breaks and leading spaces
    # specially. Escape them so passwords round-trip without shell expansion.
    result = ""
    for char in value:
        codepoint = ord(char)
        if char in "\\ :=#!":
            result += "\\" + char
        elif char == "\n":
            result += "\\n"
        elif char == "\r":
            result += "\\r"
        elif char == "\t":
            result += "\\t"
        elif codepoint > 127:
            for offset in range(0, len(char.encode("utf-16-be")), 2):
                unit = char.encode("utf-16-be")[offset : offset + 2]
                result += f"\\u{int.from_bytes(unit, 'big'):04x}"
        else:
            result += char
    return result


def main() -> None:
    names = (
        "ANDROID_KEYSTORE_BASE64",
        "ANDROID_STORE_PASSWORD",
        "ANDROID_KEY_PASSWORD",
        "ANDROID_KEY_ALIAS",
    )
    values = {name: os.environ.get(name, "") for name in names}
    if not any(values.values()):
        print("No Android signing secrets configured; using the debug signing key.")
        return
    if not all(values.values()):
        raise SystemExit("Configure all four ANDROID signing secrets, or remove them all.")

    keystore = Path(os.environ["RUNNER_TEMP"]) / "deshplayer-android.jks"
    keystore.write_bytes(base64.b64decode("".join(values[names[0]].split()), validate=True))
    keystore.chmod(0o600)
    properties = {
        "storeFile": str(keystore),
        "storePassword": values[names[1]],
        "keyPassword": values[names[2]],
        "keyAlias": values[names[3]],
    }
    config = Path("android/key.properties")
    config.write_text(
        "".join(f"{key}={property_value(value)}\n" for key, value in properties.items()),
        encoding="ascii",
    )
    config.chmod(0o600)
    print("Android keystore signing configured.")


if __name__ == "__main__":
    main()
