#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

PROJECT="$HOME/sbook-search-android"
SDK="$HOME/android-sdk"

export JAVA_HOME="$PREFIX/lib/jvm/java-21-openjdk"
export ANDROID_HOME="$SDK"
export ANDROID_SDK_ROOT="$SDK"
export PATH="$JAVA_HOME/bin:$SDK/cmdline-tools/latest/bin:$SDK/platform-tools:$PATH"

cd "$PROJECT"

echo "=== SDK REQUIREMENT ==="
grep -RniE 'compileSdk|targetSdk|buildToolsVersion' \
    app/build.gradle* 2>/dev/null || true

echo
echo "=== AVAILABLE SDK PLATFORMS ==="
sdkmanager --list | grep -E 'platforms;android-(35|36|37)' || true

echo
echo "=== INSTALL API 37 ==="

yes | sdkmanager --licenses >/dev/null 2>&1 || true

# Project is requesting android-37.0.
# Try the exact package first, then android-37.
if sdkmanager "platforms;android-37.0"; then
    echo "Installed platforms;android-37.0"
else
    echo "37.0 package unavailable; trying android-37..."
    sdkmanager "platforms;android-37"
fi

echo
echo "=== CHECK android.jar ==="

find "$SDK/platforms" \
    -maxdepth 2 \
    -name android.jar \
    -print

echo
echo "=== TERMUX AAPT2 ==="

AAPT2="$(command -v aapt2)"

touch gradle.properties

python - "$AAPT2" <<'PY'
from pathlib import Path
import sys

p = Path("gradle.properties")
aapt2 = sys.argv[1]

lines = [
    x for x in p.read_text().splitlines()
    if not x.startswith("android.aapt2FromMavenOverride=")
]

lines.append("android.aapt2FromMavenOverride=" + aapt2)
p.write_text("\n".join(lines) + "\n")
PY

echo "Using: $AAPT2"

echo
echo "=== CLEAN BROKEN RESOURCE OUTPUT ==="

rm -rf \
    app/build/intermediates \
    app/build/generated \
    app/build/tmp

./gradlew --stop 2>/dev/null || true

echo
echo "=== BUILD SBOOK ==="

./gradlew \
    --no-daemon \
    --console=plain \
    clean \
    assembleDebug

APK="$PROJECT/app/build/outputs/apk/debug/app-debug.apk"

echo
echo "=== RESULT ==="

[ -f "$APK" ] || {
    echo "ERROR: APK not generated."
    exit 1
}

ls -lh "$APK"
sha256sum "$APK"

mkdir -p "$HOME/storage/downloads"

cp -f "$APK" \
    "$HOME/storage/downloads/SBook-debug.apk"

echo
echo "===================================="
echo "SUCCESS"
echo "$HOME/storage/downloads/SBook-debug.apk"
echo "===================================="
