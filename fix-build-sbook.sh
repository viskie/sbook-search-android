#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

cd "$HOME/sbook-search-android"

FILE="app/src/main/java/org/sbook/search/IndexDatabase.java"

echo "=== REPAIR BAD SEARCH PATCH ==="

python - <<'PY'
from pathlib import Path
import re

p = Path("app/src/main/java/org/sbook/search/IndexDatabase.java")
s = p.read_text()

# Show search method declaration so we know its real mode variable.
m = re.search(
    r'(?:public|private|protected)?\s*List<SearchResult>\s+search\s*\((.*?)\)\s*\{',
    s,
    re.S
)

if not m:
    raise SystemExit("ERROR: search() method not found")

params = m.group(1)
print("search() parameters:")
print(params)

# Find boolean parameter in the REAL method.
bools = re.findall(
    r'\bboolean\s+([A-Za-z_][A-Za-z0-9_]*)',
    params
)

if not bools:
    raise SystemExit(
        "ERROR: search() has no boolean mode parameter."
    )

mode = bools[-1]
print("Using existing mode variable:", mode)

# The original SBook branch has filename mode in the `else`
# after the content-search branch. Therefore this boolean
# means content search.
s2, n = re.subn(
    r'\bif\s*\(\s*searchContent\s*\)',
    f'if ({mode})',
    s
)

if n == 0:
    if "searchContent" in s:
        raise SystemExit(
            "ERROR: searchContent exists in an unexpected form."
        )
    print("Bad searchContent reference already absent.")
else:
    print("Repaired", n, "bad searchContent reference(s).")

p.write_text(s2)
PY

echo
echo "=== CHECK FOR BAD SYMBOL ==="

if grep -n '\bsearchContent\b' "$FILE"; then
    echo "ERROR: unresolved searchContent remains."
    exit 1
else
    echo "OK: no undefined searchContent."
fi

echo
echo "=== SEARCH PATCH ==="

grep -n -A45 \
    'SBOOK_SUBSTRING_FILENAME_SEARCH' \
    "$FILE" || true

echo
echo "=== TERMUX BUILD ENVIRONMENT ==="

export JAVA_HOME="$PREFIX/lib/jvm/java-21-openjdk"
export ANDROID_HOME="$HOME/android-sdk"
export ANDROID_SDK_ROOT="$ANDROID_HOME"

export PATH="$JAVA_HOME/bin:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools:$PATH"

java -version

echo
echo "=== BUILD SBOOK ==="

chmod +x gradlew

./gradlew --stop 2>/dev/null || true

./gradlew \
    --no-daemon \
    --console=plain \
    clean \
    assembleDebug

APK="$HOME/sbook-search-android/app/build/outputs/apk/debug/app-debug.apk"

echo
echo "=== VERIFY APK ==="

[ -f "$APK" ] || {
    echo "ERROR: APK not generated."
    exit 1
}

ls -lh "$APK"
sha256sum "$APK"

echo
echo "=== COPY TO DOWNLOADS ==="

mkdir -p "$HOME/storage/downloads"

cp -f \
    "$APK" \
    "$HOME/storage/downloads/SBook-debug.apk"

echo
echo "======================================"
echo " SUCCESS"
echo "======================================"
echo
echo "$HOME/storage/downloads/SBook-debug.apk"
echo
echo "Install OVER existing SBook."
echo "Do NOT clear data/rebuild the 84K dataset."
echo
echo "Test FILE NAMES:"
echo "    ash"
echo "Expected: ashtadhyayi"
