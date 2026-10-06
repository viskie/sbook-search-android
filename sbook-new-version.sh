#!/data/data/com.termux/files/usr/bin/bash

# ============================================================
# SBOOK NEW VERSION — ONE TERMUX SCRIPT
# ============================================================
# - Termux only; NO sudo / NO VM
# - JDK 21
# - Android API 37
# - DOES NOT change Git origin
# - GitHub push uses SSH directly
# - changes visible app name to "SBook New Version"
# - fixes filename substring search: ash -> ashtadhyayi
# - DOES NOT rebuild/reindex the 84K corpus
# - DOES NOT modify progress/notification/indexing code
# - attempts APK build
# - commit + push continue even if build fails
# - stages repository source while excluding build/cache/local files
# ============================================================

set -uo pipefail

PREFIX="${PREFIX:-/data/data/com.termux/files/usr}"
HOME="${HOME:-/data/data/com.termux/files/home}"

PROJECT="$HOME/sbook-search-android"
SDK="$HOME/android-sdk"

SSH_REPO="git@github.com:viskie/sbook-search-android.git"

DB_REL="app/src/main/java/org/sbook/search/IndexDatabase.java"
DB="$PROJECT/$DB_REL"

LOG="$HOME/sbook-new-version.log"
FINAL_APK="$HOME/SBook-New-Version.apk"

PATCH_RC=999
NAME_RC=999
AAPT_RC=999
BUILD_RC=999
COMMIT_RC=999
PUSH_RC=999
SSH_STATUS="UNKNOWN"

exec > >(tee "$LOG") 2>&1

echo
echo "============================================================"
echo " SBOOK NEW VERSION"
echo " TERMUX / API 37 / SUBSTRING SEARCH / BUILD / SSH PUSH"
echo "============================================================"
date

# ============================================================
# 1. VERIFY TERMUX
# ============================================================

echo
echo "=== 1. TERMUX ==="

case "$PREFIX" in
    /data/data/com.termux/*)
        echo "Environment : Termux"
        ;;
    *)
        echo "FATAL: this script is Termux-only."
        exit 10
        ;;
esac

echo "PREFIX      : $PREFIX"
echo "HOME        : $HOME"
echo "Project     : $PROJECT"

# ============================================================
# 2. PACKAGES
# ============================================================

echo
echo "=== 2. PACKAGES ==="

pkg install -y \
    git \
    openssh \
    python \
    unzip \
    wget \
    openjdk-21 || true

export JAVA_HOME="$PREFIX/lib/jvm/java-21-openjdk"
export ANDROID_HOME="$SDK"
export ANDROID_SDK_ROOT="$SDK"

export PATH="$JAVA_HOME/bin:$SDK/cmdline-tools/latest/bin:$SDK/platform-tools:$PREFIX/bin:$PATH"

echo
echo "--- JAVA ---"
java -version || true

# ============================================================
# 3. REPOSITORY
# ============================================================

echo
echo "=== 3. REPOSITORY ==="

if [ ! -d "$PROJECT/.git" ]; then

    echo "Repository absent; cloning over SSH..."

    git clone "$SSH_REPO" "$PROJECT" || exit 20
fi

cd "$PROJECT" || exit 21

ORIGIN="$(git remote get-url origin 2>/dev/null || true)"
BRANCH="$(git branch --show-current)"

[ -n "$BRANCH" ] || BRANCH="main"

echo "Existing origin : $ORIGIN"
echo "Branch          : $BRANCH"
echo "HEAD            : $(git rev-parse --short HEAD)"
echo
echo "Origin will NOT be modified."

# ============================================================
# 4. SSH
# ============================================================

echo
echo "=== 4. GITHUB SSH ==="

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if ! grep -q 'github.com' "$HOME/.ssh/known_hosts" 2>/dev/null; then
    ssh-keyscan github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
fi

chmod 600 "$HOME/.ssh/known_hosts" 2>/dev/null || true

echo "Private key candidates:"

find "$HOME/.ssh" \
    -maxdepth 1 \
    -type f \
    -name 'id_*' \
    ! -name '*.pub' \
    -printf '  %f\n' \
    2>/dev/null || true

SSH_OUT="$(
    ssh \
        -o BatchMode=yes \
        -o StrictHostKeyChecking=yes \
        -T git@github.com \
        2>&1
)"

echo "$SSH_OUT"

if printf '%s\n' "$SSH_OUT" |
   grep -qi 'successfully authenticated'; then

    SSH_STATUS="PASS"

else

    SSH_STATUS="NOT CONFIRMED"

fi

echo "SSH status: $SSH_STATUS"

# ============================================================
# 5. API 37
# ============================================================

echo
echo "=== 5. ANDROID API 37 ==="

PLATFORM_DIR=""

if [ -f "$SDK/platforms/android-37.0/android.jar" ]; then

    PLATFORM_DIR="$SDK/platforms/android-37.0"

elif [ -f "$SDK/platforms/android-37/android.jar" ]; then

    PLATFORM_DIR="$SDK/platforms/android-37"

fi

if [ -z "$PLATFORM_DIR" ] && command -v sdkmanager >/dev/null 2>&1; then

    echo "API 37 absent; attempting installation..."

    yes | sdkmanager --licenses >/dev/null 2>&1 || true

    sdkmanager "platforms;android-37.0" 2>/dev/null ||
        sdkmanager "platforms;android-37" 2>/dev/null ||
        true

fi

if [ -f "$SDK/platforms/android-37.0/android.jar" ]; then

    PLATFORM_DIR="$SDK/platforms/android-37.0"

elif [ -f "$SDK/platforms/android-37/android.jar" ]; then

    PLATFORM_DIR="$SDK/platforms/android-37"

fi

if [ -n "$PLATFORM_DIR" ]; then

    echo "API 37 platform:"
    ls -lh "$PLATFORM_DIR/android.jar"

else

    echo "WARNING: API 37 android.jar unavailable."
    echo "Build may fail; commit/push will still continue."

fi

# ============================================================
# 6. LOCAL ANDROID CONFIG
# ============================================================

echo
echo "=== 6. ANDROID CONFIG ==="

cat > local.properties <<EOF
sdk.dir=$SDK
EOF

# Keep Termux's native aapt2 override when available.
AAPT2="$(command -v aapt2 2>/dev/null || true)"

if [ -n "$AAPT2" ]; then

    echo "aapt2: $AAPT2"
    "$AAPT2" version || true

    touch gradle.properties

    sed -i \
        '/^android\.aapt2FromMavenOverride=/d' \
        gradle.properties

    printf '\nandroid.aapt2FromMavenOverride=%s\n' \
        "$AAPT2" >> gradle.properties

else

    echo "aapt2 not currently found."

fi

# ============================================================
# 7. CHANGE VISIBLE APP NAME
# ============================================================

echo
echo "=== 7. APP NAME: SBook New Version ==="

python - "$PROJECT" <<'PY'
from pathlib import Path
import re
import sys

root = Path(sys.argv[1])

strings = root / "app/src/main/res/values/strings.xml"
manifest = root / "app/src/main/AndroidManifest.xml"

changed = False

if strings.exists():
    s = strings.read_text()

    m = re.search(
        r'(<string\s+name=["\']app_name["\']\s*>)(.*?)(</string>)',
        s,
        flags=re.S
    )

    if m:
        new = m.group(1) + "SBook New Version" + m.group(3)

        if m.group(0) != new:
            s = s[:m.start()] + new + s[m.end():]
            strings.write_text(s)
            changed = True

        print("app_name -> SBook New Version")
        sys.exit(0)

if manifest.exists():
    s = manifest.read_text()

    # Only change a literal application label.
    m = re.search(
        r'android:label=(["\'])(?!@)(.*?)\1',
        s
    )

    if m:
        quote = m.group(1)
        replacement = f'android:label={quote}SBook New Version{quote}'

        s = s[:m.start()] + replacement + s[m.end():]
        manifest.write_text(s)

        print("Manifest label -> SBook New Version")
        sys.exit(0)

print("ERROR: app label location could not be determined safely.")
sys.exit(40)
PY

NAME_RC=$?

echo "Name RC: $NAME_RC"

# ============================================================
# 8. EXACT FILENAME SUBSTRING SEARCH FIX
# ============================================================

echo
echo "=== 8. FILENAME SUBSTRING SEARCH ==="

if [ ! -f "$DB" ]; then

    echo "ERROR: $DB_REL missing."
    PATCH_RC=50

else

python - "$DB" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()

MARKER = "SBOOK_SUBSTRING_FILENAME_SEARCH"

required = [
    "WHERE name LIKE ? COLLATE NOCASE",
    "String sqlArgument",
    "if (contents)",
    'sqlArgument = "%" + filenameQuery + "%";'
]

# Already correctly patched.
if MARKER in s:

    missing = [x for x in required if x not in s]

    if not missing:
        print("Substring search patch already present.")
        sys.exit(0)

    print("ERROR: existing patch is incomplete:")
    for x in missing:
        print(" missing:", x)

    sys.exit(51)


# Repair the previously known accidental undeclared block,
# but only if it matches exactly.
broken = '''        String sqlArgument;

        if (searchContent) {
            sqlArgument = query;
        } else {
            String filenameQuery =
                    rawQuery == null ? "" : rawQuery.trim();

            sqlArgument = "%" + filenameQuery + "%";
        }

'''

if broken in s:
    s = s.replace(broken, "", 1)


if "searchContent" in s and "boolean searchContent" not in s:
    print("ERROR: undeclared searchContent remains in source.")
    print("Refusing an unsafe guessed edit.")
    sys.exit(52)


old_sql = '''            sql = "SELECT d.path,d.name,'' FROM filename_fts " +
                    "JOIN documents d ON d.id=filename_fts.docid " +
                    "WHERE filename_fts MATCH ? ORDER BY d.name COLLATE NOCASE LIMIT ?";'''

new_sql = '''            // SBOOK_SUBSTRING_FILENAME_SEARCH
            // Direct substring lookup against existing documents.
            // ash -> ashtadhyayi. No corpus reindex required.
            sql = "SELECT path,name,'' FROM documents " +
                    "WHERE name LIKE ? COLLATE NOCASE " +
                    "ORDER BY name COLLATE NOCASE LIMIT ?";'''


old_call = '''        try (Cursor cursor = db.rawQuery(sql, new String[]{query, Integer.toString(limit)})) {'''

new_call = '''        String sqlArgument;
        if (contents) {
            sqlArgument = query;
        } else {
            String filenameQuery =
                    rawQuery == null ? "" : rawQuery.trim();
            sqlArgument = "%" + filenameQuery + "%";
        }

        try (Cursor cursor = db.rawQuery(
                sql,
                new String[]{sqlArgument, Integer.toString(limit)})) {'''


if "boolean contents" not in s:
    print("ERROR: expected boolean contents parameter not found.")
    sys.exit(53)

if "String rawQuery" not in s:
    print("ERROR: expected String rawQuery parameter not found.")
    sys.exit(54)

if old_sql not in s:
    print("ERROR: original filename FTS SQL not found.")
    print("Source left unchanged.")
    sys.exit(55)

if old_call not in s:
    print("ERROR: original rawQuery call not found.")
    print("Source left unchanged.")
    sys.exit(56)


s = s.replace(old_sql, new_sql, 1)
s = s.replace(old_call, new_call, 1)

p.write_text(s)

print("SEARCH PATCH APPLIED")
print("filename: documents.name LIKE %rawQuery%")
print("content : existing FTS unchanged")
print("reindex : NOT REQUIRED")
PY

PATCH_RC=$?

fi

echo "Patch RC: $PATCH_RC"

if [ "$PATCH_RC" -eq 0 ]; then

    grep -n \
        -A18 \
        -B8 \
        'SBOOK_SUBSTRING_FILENAME_SEARCH' \
        "$DB" || true

fi

# ============================================================
# 9. DIRECT AAPT2/API37 DIAGNOSTIC
# ============================================================

echo
echo "=== 9. AAPT2 / API 37 TEST ==="

if [ -n "${AAPT2:-}" ] &&
   [ -n "$PLATFORM_DIR" ] &&
   [ -f "$PLATFORM_DIR/android.jar" ]; then

    TMPAPK="$PREFIX/tmp/sbook-aapt37-test.apk"

    rm -f "$TMPAPK"

    "$AAPT2" link \
        -I "$PLATFORM_DIR/android.jar" \
        --manifest app/src/main/AndroidManifest.xml \
        -o "$TMPAPK"

    AAPT_RC=$?

    rm -f "$TMPAPK"

else

    echo "Direct aapt2 test unavailable."
    AAPT_RC=98

fi

echo "AAPT2/API37 RC: $AAPT_RC"

# ============================================================
# 10. BUILD
# ============================================================

echo
echo "============================================================"
echo " 10. BUILD SBOOK NEW VERSION"
echo "============================================================"

chmod +x gradlew

./gradlew --stop >/dev/null 2>&1 || true

rm -rf \
    app/build \
    build \
    .gradle

./gradlew \
    --no-daemon \
    --console=plain \
    clean \
    assembleDebug

BUILD_RC=$?

echo
echo "Build RC: $BUILD_RC"

APK="$PROJECT/app/build/outputs/apk/debug/app-debug.apk"

if [ "$BUILD_RC" -eq 0 ] && [ -f "$APK" ]; then

    cp -f "$APK" "$FINAL_APK"

    echo
    echo "BUILD SUCCESS"

    ls -lh "$FINAL_APK"
    sha256sum "$FINAL_APK"

else

    echo
    echo "BUILD FAILED."
    echo "Commit and SSH push will continue."

fi

# ============================================================
# 11. GIT EXCLUSIONS
# ============================================================

echo
echo "=== 11. GIT EXCLUSIONS ==="

touch .gitignore

cat >> .gitignore <<'EOF'

# Android/local build artifacts
.gradle/
**/.gradle/
build/
**/build/
.idea/
**/.idea/
.cxx/
**/.cxx/
.externalNativeBuild/
**/.externalNativeBuild/
local.properties
*.apk
*.aab
*.ap_
*.dex
*.class
*.log
*.tmp
*.temp
*.cache
__pycache__/
*.pyc
EOF

python - <<'PY'
from pathlib import Path

p = Path(".gitignore")

seen = set()
out = []

for line in p.read_text().splitlines():

    x = line.strip()

    if x and not x.startswith("#"):

        if x in seen:
            continue

        seen.add(x)

    out.append(line)

p.write_text("\n".join(out) + "\n")
PY

# Machine-specific Termux AAPT path must not be committed.
if [ -f gradle.properties ]; then

    sed -i \
        '/^android\.aapt2FromMavenOverride=/d' \
        gradle.properties

fi

# ============================================================
# 12. STAGE ALL REPOSITORY SOURCE
# ============================================================

echo
echo "============================================================"
echo " 12. STAGE ALL SOURCE"
echo "============================================================"

git reset >/dev/null 2>&1 || true

git add -A

# Safety: remove generated/local artifacts from staging.
while IFS= read -r FILE
do

    case "$FILE" in

        local.properties|\
        */local.properties|\
        .gradle/*|\
        */.gradle/*|\
        build/*|\
        */build/*|\
        .idea/*|\
        */.idea/*|\
        .cxx/*|\
        */.cxx/*|\
        .externalNativeBuild/*|\
        */.externalNativeBuild/*|\
        *.apk|\
        *.aab|\
        *.ap_|\
        *.dex|\
        *.class|\
        *.log|\
        *.tmp|\
        *.temp|\
        *.cache)

            git reset -- "$FILE" >/dev/null 2>&1 || true
            ;;

    esac

done < <(git diff --cached --name-only)

echo
echo "--- STAGED FILES ---"

git diff --cached --name-status

echo
echo "--- STAGED COUNT ---"

git diff --cached --name-only | wc -l

echo
echo "--- DIFF CHECK ---"

git diff --cached --check || true

# ============================================================
# 13. COMMIT EVEN IF BUILD FAILED
# ============================================================

echo
echo "============================================================"
echo " 13. COMMIT"
echo "============================================================"

if git diff --cached --quiet; then

    echo "Nothing new to commit."
    COMMIT_RC=0

else

    if [ "$BUILD_RC" -eq 0 ]; then

        MESSAGE="SBook New Version: filename substring search"

    else

        MESSAGE="SBook New Version: filename substring search; build pending"

    fi

    git commit -m "$MESSAGE"
    COMMIT_RC=$?

fi

echo "Commit RC: $COMMIT_RC"

# ============================================================
# 14. RESTORE LOCAL TERMUX AAPT OVERRIDE
# ============================================================

if [ -n "${AAPT2:-}" ]; then

    touch gradle.properties

    sed -i \
        '/^android\.aapt2FromMavenOverride=/d' \
        gradle.properties

    printf '\nandroid.aapt2FromMavenOverride=%s\n' \
        "$AAPT2" >> gradle.properties

fi

# ============================================================
# 15. SSH PUSH
#
# IMPORTANT:
# Existing "origin" is NOT changed.
# We push directly to the SSH GitHub URL.
# ============================================================

echo
echo "============================================================"
echo " 15. SSH PUSH"
echo "============================================================"

echo "Existing origin remains:"
git remote get-url origin

echo
echo "Push destination:"
echo "$SSH_REPO"

echo
echo "Branch:"
echo "$BRANCH"

GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=yes" \
    git push "$SSH_REPO" "$BRANCH:$BRANCH"

PUSH_RC=$?

# ============================================================
# 16. FINAL REPORT
# ============================================================

echo
echo
echo "============================================================"
echo " SBOOK NEW VERSION — FINAL REPORT"
echo "============================================================"

echo "Environment     : Termux"
echo "App name        : SBook New Version"
echo "Project         : $PROJECT"
echo "API             : 37"
echo "Java            : 21"
echo "Branch          : $BRANCH"
echo "Original origin : $(git remote get-url origin)"
echo "Push transport  : SSH"
echo "Push target     : $SSH_REPO"
echo "SSH auth        : $SSH_STATUS"
echo "Name RC         : $NAME_RC"
echo "Search patch RC : $PATCH_RC"
echo "AAPT2/API37 RC  : $AAPT_RC"
echo "Build RC        : $BUILD_RC"
echo "Commit RC       : $COMMIT_RC"
echo "Push RC         : $PUSH_RC"
echo "HEAD            : $(git rev-parse --short HEAD)"
echo "Log             : $LOG"

if [ -f "$FINAL_APK" ]; then

    echo "APK             : $FINAL_APK"
    echo "APK SHA256      : $(sha256sum "$FINAL_APK" | awk '{print $1}')"

else

    echo "APK             : NOT PRODUCED"

fi

echo
echo "Filename search : substring LIKE %query%"
echo "Example         : ash -> ashtadhyayi"
echo "84K reindex     : NO"
echo "Origin modified : NO"

echo
echo "--- LATEST COMMIT ---"
git --no-pager log -1 --oneline

echo
echo "--- WORKING TREE ---"
git status --short

echo
echo "============================================================"

# Final status follows SSH push because push is required even
# when compilation failed.
exit "$PUSH_RC"
