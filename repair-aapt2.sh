#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

echo "=== CURRENT TERMUX ==="
echo "PREFIX=$PREFIX"
uname -m
termux-info 2>/dev/null || true

echo
echo "=== CURRENT REPOSITORIES ==="
grep -Rhv '^[[:space:]]*#' \
    "$PREFIX/etc/apt/sources.list" \
    "$PREFIX/etc/apt/sources.list.d/"*.list \
    2>/dev/null || true

echo
echo "=== SWITCH MAIN REPOSITORY ==="

cat > "$PREFIX/etc/apt/sources.list" <<'EOF'
deb https://packages.termux.dev/apt/termux-main stable main
EOF

# Disable stale main-repository definitions that could win over
# packages.termux.dev. Preserve the files as backups.
mkdir -p "$HOME/.termux-repo-backup"

for f in "$PREFIX/etc/apt/sources.list.d/"*.list; do
    [ -e "$f" ] || continue

    if grep -qE \
       'termux-main|packages-cf\.termux|grimler|termux\.net|bintray' \
       "$f"; then

        cp -f "$f" \
           "$HOME/.termux-repo-backup/$(basename "$f").bak"

        mv "$f" "$f.disabled"
    fi
done

echo
echo "=== CLEAN APT CACHE ==="

apt clean
rm -rf "$PREFIX/var/lib/apt/lists/"*

echo
echo "=== UPDATE ==="

apt update

echo
echo "=== AVAILABLE AAPT VERSION ==="

apt-cache policy aapt || true
apt-cache policy aapt2 || true

echo
echo "=== REMOVE OLD AAPT2 ==="

OLD_AAPT2="$(command -v aapt2 || true)"

if [ -n "$OLD_AAPT2" ]; then
    echo "Old binary: $OLD_AAPT2"
    "$OLD_AAPT2" version || true
fi

# Current upstream package is named aapt.
# Don't fail if old installations use aapt2 as a separate package.

apt remove -y aapt2 2>/dev/null || true

echo
echo "=== INSTALL CURRENT AAPT ==="

apt install -y --reinstall aapt

hash -r

echo
echo "=== LOCATE AAPT2 ==="

AAPT2="$(command -v aapt2 || true)"

if [ -z "$AAPT2" ]; then
    echo "ERROR: current aapt package did not provide aapt2."
    echo
    echo "Package contents:"
    dpkg -L aapt || true
    exit 20
fi

echo "$AAPT2"

echo
echo "=== VERSION ==="

aapt2 version

echo
echo "=== PACKAGE ==="

dpkg -s aapt 2>/dev/null |
    grep -E '^(Package|Version|Architecture):' || true

echo
echo "=== TEST API 37 ==="

JAR="$HOME/android-sdk/platforms/android-37.0/android.jar"

if [ ! -f "$JAR" ]; then
    JAR="$HOME/android-sdk/platforms/android-37/android.jar"
fi

test -f "$JAR" || {
    echo "ERROR: API 37 android.jar not found."
    exit 21
}

TMP="$(mktemp -d)"

cat > "$TMP/AndroidManifest.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest
    xmlns:android="http://schemas.android.com/apk/res/android"
    package="org.sbook.aapt2test">

    <uses-sdk
        android:minSdkVersion="26"
        android:targetSdkVersion="37" />

    <application android:label="SBookTest" />
</manifest>
EOF

set +e

"$AAPT2" link \
    -I "$JAR" \
    --manifest "$TMP/AndroidManifest.xml" \
    -o "$TMP/test.apk" \
    >"$TMP/test.log" 2>&1

RC=$?

set -e

cat "$TMP/test.log"

if [ "$RC" -ne 0 ]; then
    echo
    echo "======================================"
    echo " REPOSITORY UPDATED, BUT AAPT2"
    echo " STILL CANNOT READ API 37"
    echo "======================================"
    echo
    echo "aapt2:"
    aapt2 version || true
    echo
    echo "Do NOT rebuild SBook yet."
    echo "No SBook source was changed."
    rm -rf "$TMP"
    exit 22
fi

rm -rf "$TMP"

echo
echo "======================================"
echo " API 37 AAPT2 TEST PASSED"
echo "======================================"

PROJECT="$HOME/sbook-search-android"

if [ ! -d "$PROJECT" ]; then
    echo "SBook directory not found."
    exit 0
fi

cd "$PROJECT"

echo
echo "=== CONFIGURE SBOOK ==="

touch gradle.properties

python - "$AAPT2" <<'PY'
from pathlib import Path
import sys

p = Path("gradle.properties")
binary = sys.argv[1]

lines = p.read_text().splitlines()

lines = [
    x for x in lines
    if not x.startswith("android.aapt2FromMavenOverride=")
]

lines.append(
    "android.aapt2FromMavenOverride=" + binary
)

p.write_text("\n".join(lines) + "\n")
PY

cat > local.properties <<EOF
sdk.dir=$HOME/android-sdk
EOF

export JAVA_HOME="$PREFIX/lib/jvm/java-21-openjdk"
export ANDROID_HOME="$HOME/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"
export PATH="$JAVA_HOME/bin:$PATH"

echo
echo "=== SEARCH PATCH ==="

DB="app/src/main/java/org/sbook/search/IndexDatabase.java"

if grep -q \
   'SBOOK_SUBSTRING_FILENAME_SEARCH\|WHERE name LIKE ? COLLATE NOCASE' \
   "$DB"; then
    echo "Search patch present."
else
    echo "ERROR: search patch is not present."
    echo "Stopping rather than building the wrong APK."
    exit 30
fi

echo
echo "=== BUILD ==="

./gradlew --stop 2>/dev/null || true
rm -rf app/build

./gradlew \
    --no-daemon \
    --console=plain \
    clean \
    assembleDebug

APK="$PROJECT/app/build/outputs/apk/debug/app-debug.apk"

test -f "$APK"

mkdir -p "$HOME/storage/downloads"

cp -f "$APK" \
    "$HOME/storage/downloads/SBook-debug.apk"

echo
echo "======================================"
echo " SBOOK BUILD SUCCESS"
echo "======================================"
echo
echo "$HOME/storage/downloads/SBook-debug.apk"
echo
echo "API 37 retained."
echo "Search patch retained."
echo "No reindex."
