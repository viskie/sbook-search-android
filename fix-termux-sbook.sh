#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

PROJECT="$HOME/sbook-search-android"
SDK="$HOME/android-sdk"

echo "======================================"
echo " FIX TERMUX + BUILD SBOOK API 37"
echo "======================================"

# ----------------------------------------------------------
# 1. Update Termux repositories/packages
# ----------------------------------------------------------

echo
echo "=== TERMUX UPDATE ==="

pkg update -y
pkg upgrade -y

pkg install -y \
    openjdk-21 \
    aapt2 \
    git \
    wget \
    unzip

hash -r

echo
echo "=== AAPT2 AFTER UPDATE ==="

AAPT2="$(command -v aapt2)"

echo "Binary: $AAPT2"
aapt2 version || true

echo
echo "Installed package:"
dpkg -s aapt2 2>/dev/null | grep -E '^(Package|Version):' || true

# ----------------------------------------------------------
# 2. Environment
# ----------------------------------------------------------

export JAVA_HOME="$PREFIX/lib/jvm/java-21-openjdk"
export ANDROID_HOME="$SDK"
export ANDROID_SDK_ROOT="$SDK"

export PATH="$JAVA_HOME/bin:$SDK/cmdline-tools/latest/bin:$SDK/platform-tools:$PATH"

java -version

# ----------------------------------------------------------
# 3. Verify Android SDK command tools
# ----------------------------------------------------------

if [ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]; then

    echo
    echo "=== INSTALL SDK COMMAND TOOLS ==="

    TMP="$(mktemp -d)"

    wget -q --show-progress \
      -O "$TMP/tools.zip" \
      "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"

    unzip -q "$TMP/tools.zip" -d "$TMP/out"

    mkdir -p "$SDK/cmdline-tools/latest"

    cp -a \
      "$TMP/out/cmdline-tools/." \
      "$SDK/cmdline-tools/latest/"

    rm -rf "$TMP"
fi

# ----------------------------------------------------------
# 4. API 37
# ----------------------------------------------------------

echo
echo "=== API 37 ==="

yes | sdkmanager --licenses >/dev/null 2>&1 || true

if sdkmanager --list | grep -q 'platforms;android-37.0'; then

    PLATFORM_PACKAGE="platforms;android-37.0"
    PLATFORM_DIR="$SDK/platforms/android-37.0"

else

    PLATFORM_PACKAGE="platforms;android-37"
    PLATFORM_DIR="$SDK/platforms/android-37"

fi

sdkmanager "$PLATFORM_PACKAGE" "platform-tools"

ANDROID_JAR="$PLATFORM_DIR/android.jar"

test -f "$ANDROID_JAR" || {
    echo "ERROR: API-37 android.jar missing:"
    echo "$ANDROID_JAR"
    exit 1
}

ls -lh "$ANDROID_JAR"

# ----------------------------------------------------------
# 5. CRITICAL TEST:
#    Can the updated native Termux aapt2 read API 37?
# ----------------------------------------------------------

echo
echo "=== TEST AAPT2 AGAINST API 37 ==="

TMP="$(mktemp -d)"

cat > "$TMP/AndroidManifest.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="org.sbook.aapt2test">

    <uses-sdk
        android:minSdkVersion="26"
        android:targetSdkVersion="37" />

    <application android:label="test" />

</manifest>
EOF

set +e

"$AAPT2" link \
    -I "$ANDROID_JAR" \
    --manifest "$TMP/AndroidManifest.xml" \
    -o "$TMP/test.apk" \
    >"$TMP/aapt.log" 2>&1

RC=$?

set -e

cat "$TMP/aapt.log"

if [ "$RC" -ne 0 ]; then

    echo
    echo "======================================"
    echo " AAPT2 STILL INCOMPATIBLE"
    echo "======================================"
    echo
    echo "Termux currently supplies:"
    "$AAPT2" version || true
    echo
    echo "It still cannot read:"
    echo "$ANDROID_JAR"
    echo
    echo "Stopping here instead of modifying"
    echo "SBook or downgrading compileSdk."
    echo
    echo "Your project has NOT been changed."

    rm -rf "$TMP"
    exit 20
fi

rm -rf "$TMP"

echo
echo "API-37 android.jar successfully loaded."
echo "Native Termux toolchain is usable."

# ----------------------------------------------------------
# 6. SBook
# ----------------------------------------------------------

test -d "$PROJECT" || {
    echo "ERROR: $PROJECT not found."
    exit 1
}

cd "$PROJECT"

echo
echo "=== SBOOK SDK CONFIG ==="

grep -RniE \
    'compileSdk|targetSdk|buildToolsVersion' \
    app/build.gradle* \
    gradle/libs.versions.toml \
    2>/dev/null || true

# ----------------------------------------------------------
# 7. Force Gradle to use the WORKING Termux aapt2
# ----------------------------------------------------------

touch gradle.properties

python - "$AAPT2" <<'PY'
from pathlib import Path
import sys

p = Path("gradle.properties")
aapt2 = sys.argv[1]

lines = p.read_text().splitlines()

lines = [
    x for x in lines
    if not x.startswith("android.aapt2FromMavenOverride=")
]

lines.append(
    "android.aapt2FromMavenOverride=" + aapt2
)

p.write_text("\n".join(lines) + "\n")
PY

cat > local.properties <<EOF
sdk.dir=$SDK
EOF

echo
echo "=== AAPT2 OVERRIDE ==="

grep 'android.aapt2FromMavenOverride' gradle.properties

# ----------------------------------------------------------
# 8. Verify search patch
# ----------------------------------------------------------

DB="app/src/main/java/org/sbook/search/IndexDatabase.java"

echo
echo "=== SEARCH PATCH STATUS ==="

if grep -q 'SBOOK_SUBSTRING_FILENAME_SEARCH' "$DB"; then

    echo "Substring filename-search patch PRESENT."

elif grep -q 'WHERE name LIKE ? COLLATE NOCASE' "$DB"; then

    echo "Substring filename-search SQL PRESENT."

else

    echo
    echo "WARNING:"
    echo "The filename substring search patch is NOT present."
    echo
    echo "I am NOT automatically rewriting IndexDatabase.java here,"
    echo "because the previous automatic patch caused the"
    echo "searchContent compile regression."
    echo
    echo "Toolchain is fixed; source needs the search patch."
    exit 30
fi

# ----------------------------------------------------------
# 9. Clean stale Gradle/resource output
# ----------------------------------------------------------

echo
echo "=== CLEAN ==="

./gradlew --stop 2>/dev/null || true

rm -rf \
    app/build \
    .gradle

# ----------------------------------------------------------
# 10. Build
# ----------------------------------------------------------

echo
echo "=== BUILD SBOOK ==="

chmod +x gradlew

./gradlew \
    --no-daemon \
    --console=plain \
    clean \
    assembleDebug

# ----------------------------------------------------------
# 11. APK
# ----------------------------------------------------------

APK="$PROJECT/app/build/outputs/apk/debug/app-debug.apk"

test -f "$APK" || {
    echo "ERROR: APK not generated."
    exit 1
}

echo
echo "=== APK ==="

ls -lh "$APK"
sha256sum "$APK"

# ----------------------------------------------------------
# 12. Copy to Downloads
# ----------------------------------------------------------

if [ -d "$HOME/storage/downloads" ]; then

    cp -f \
      "$APK" \
      "$HOME/storage/downloads/SBook-debug.apk"

    OUTPUT="$HOME/storage/downloads/SBook-debug.apk"

else

    cp -f \
      "$APK" \
      "$HOME/SBook-debug.apk"

    OUTPUT="$HOME/SBook-debug.apk"

fi

echo
echo "======================================"
echo " SUCCESS"
echo "======================================"
echo
echo "$OUTPUT"
echo
echo "API 37 retained."
echo "Native Termux build."
echo "No Debian/proot."
echo "No reindex."
