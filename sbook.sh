#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

REPO="https://github.com/viskie/sbook-search-android.git"
PROJECT="$HOME/sbook-search-android"
SDK="$HOME/android-sdk"
APK="$PROJECT/app/build/outputs/apk/debug/app-debug.apk"
OUT="$HOME/storage/downloads/SBook-debug.apk"

echo "=== 1. DEPENDENCIES ==="
pkg update -y
pkg install -y git python openjdk-21 wget unzip aapt2

export JAVA_HOME="$PREFIX/lib/jvm/java-21-openjdk"
export ANDROID_HOME="$SDK"
export ANDROID_SDK_ROOT="$SDK"
export PATH="$JAVA_HOME/bin:$SDK/cmdline-tools/latest/bin:$SDK/platform-tools:$PATH"

java -version

echo "=== 2. ANDROID SDK ==="
mkdir -p "$SDK/cmdline-tools"

if [ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]; then
    cd "$HOME"
    rm -rf cmdtools commandlinetools.zip

    wget -O commandlinetools.zip \
      "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"

    mkdir cmdtools
    unzip -q commandlinetools.zip -d cmdtools

    mkdir -p "$SDK/cmdline-tools/latest"
    cp -a cmdtools/cmdline-tools/. "$SDK/cmdline-tools/latest/"

    rm -rf cmdtools commandlinetools.zip
fi

export PATH="$JAVA_HOME/bin:$SDK/cmdline-tools/latest/bin:$SDK/platform-tools:$PATH"

yes | sdkmanager --licenses >/dev/null 2>&1 || true

sdkmanager \
    "platforms;android-35" \
    "build-tools;35.0.0" \
    "platform-tools"

echo "=== 3. SBOOK SOURCE ==="

if [ ! -d "$PROJECT/.git" ]; then
    git clone "$REPO" "$PROJECT"
fi

cd "$PROJECT"

# Remove accidental project created by old build.sh.
if [ -d "$PROJECT/ManyStopNav" ]; then
    echo "Removing accidental ManyStopNav..."
    rm -rf "$PROJECT/ManyStopNav"
fi

# Pull only when source has no local modifications.
if git diff --quiet && git diff --cached --quiet; then
    git fetch origin
    git pull --ff-only origin main || true
else
    echo "Existing local SBook changes preserved."
fi

echo "Commit:"
git log -1 --oneline

echo "=== 4. SDK CONFIGURATION ==="

cat > local.properties <<EOF
sdk.dir=$SDK
EOF

AAPT2="$(command -v aapt2)"

[ -x "$AAPT2" ] || {
    echo "ERROR: Termux aapt2 unavailable"
    exit 1
}

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

echo "=== 5. FIX ash -> ashtadhyayi SEARCH ==="

FILE="app/src/main/java/org/sbook/search/IndexDatabase.java"

[ -f "$FILE" ] || {
    echo "ERROR: $FILE missing"
    exit 1
}

python - <<'PY'
from pathlib import Path
import re
import shutil

p = Path("app/src/main/java/org/sbook/search/IndexDatabase.java")
s = p.read_text()

MARKER = "SBOOK_SUBSTRING_FILENAME_SEARCH"

if MARKER in s:
    print("Search patch already installed.")
    raise SystemExit(0)

backup = Path(str(p) + ".before-search-fix")
if not backup.exists():
    shutil.copy2(p, backup)

# Replace filename FTS SQL only.
pattern = re.compile(
    r'''(?P<indent>[ \t]*)
    sql\s*=\s*
    "SELECT d\.path,d\.name,'' FROM filename_fts "\s*\+\s*
    "JOIN documents d ON d\.id=filename_fts\.docid "\s*\+\s*
    "WHERE filename_fts MATCH \? ORDER BY d\.name COLLATE NOCASE LIMIT \?";''',
    re.VERBOSE
)

m = pattern.search(s)

if not m:
    print("ERROR: expected filename_fts search SQL not found.")
    print("No source modifications made.")
    raise SystemExit(2)

indent = m.group("indent")

new_sql = indent + '''/*
         * SBOOK_SUBSTRING_FILENAME_SEARCH
         * ash -> ashtadhyayi
         * Filename only. Document full-text FTS remains unchanged.
         */
        sql = "SELECT path,name,'' FROM documents " +
              "WHERE name LIKE ? COLLATE NOCASE " +
              "ORDER BY name COLLATE NOCASE LIMIT ?";'''

candidate = s[:m.start()] + new_sql + s[m.end():]

# Change argument for filename mode from FTS query to %substring%.
raw = re.compile(
    r'''try\s*\(\s*Cursor\s+cursor\s*=\s*
    db\.rawQuery\(
      sql,\s*
      new\s+String\[\]\s*
      \{\s*query\s*,\s*Integer\.toString\(limit\)\s*\}
    \)\s*\)''',
    re.VERBOSE
)

rm = raw.search(candidate)

if not rm:
    print("ERROR: expected rawQuery call not found.")
    print("No source modifications made.")
    raise SystemExit(3)

new_raw = '''String sqlArgument;

        if (searchContent) {
            sqlArgument = query;
        } else {
            String filenameQuery =
                    rawQuery == null ? "" : rawQuery.trim();

            sqlArgument = "%" + filenameQuery + "%";
        }

        try (Cursor cursor = db.rawQuery(
                sql,
                new String[]{
                        sqlArgument,
                        Integer.toString(limit)
                }))'''

candidate = candidate[:rm.start()] + new_raw + candidate[rm.end():]

p.write_text(candidate)

print("Search patched.")
print("Reindex/progress code untouched.")
PY

echo "=== 6. VERIFY PROJECT ==="

[ -f gradlew ] || {
    echo "ERROR: SBook gradlew missing"
    exit 1
}

[ -d app ] || {
    echo "ERROR: SBook app/ missing"
    exit 1
}

chmod +x gradlew

echo "Project:"
pwd

echo "Java:"
java -version

echo "Gradle:"
./gradlew --version

echo "=== 7. BUILD SBOOK ==="

# IMPORTANT:
# NEVER execute ./build.sh.
# Build the actual SBook Android project directly.

./gradlew clean assembleDebug

echo "=== 8. VERIFY APK ==="

[ -f "$APK" ] || {
    echo "ERROR: SBook APK was not generated."
    echo "APKs found:"
    find "$PROJECT" -type f -name '*.apk' -print 2>/dev/null || true
    exit 1
}

ls -lh "$APK"
sha256sum "$APK"

echo "=== 9. COPY APK TO DOWNLOADS ==="

# Request shared-storage permission only if needed.
if [ ! -d "$HOME/storage/downloads" ]; then
    echo "Termux storage permission required."
    termux-setup-storage || true

    echo
    echo "Grant Files/Storage permission, then press ENTER."
    read -r
fi

mkdir -p "$HOME/storage/downloads"
cp -f "$APK" "$OUT"

echo
echo "======================================"
echo " SUCCESS"
echo "======================================"
echo
echo "SBook APK:"
echo "$APK"
echo
echo "Copied to:"
echo "$OUT"
echo
ls -lh "$OUT"
echo
echo "Install SBook-debug.apk OVER existing SBook."
echo "DO NOT uninstall existing SBook."
echo "DO NOT clear app data."
echo "DO NOT rebuild the 84K dataset."
echo
echo "Test FILE NAMES:"
echo "  ash"
echo "  ashta"
echo "  dhya"
echo
echo "Expected: ashtadhyayi filenames."
echo
echo "Future rebuild command:"
echo "  cd ~/sbook-search-android && ./gradlew assembleDebug"
echo "======================================"
