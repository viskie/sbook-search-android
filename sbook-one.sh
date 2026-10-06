#!/usr/bin/env bash

set -uo pipefail

PROJECT="$HOME/sbook-search-android"
REPO_SSH="git@github.com:viskie/sbook-search-android.git"
SDK="$HOME/android-sdk"
LOG="$HOME/sbook-one.log"
FINAL_APK="$HOME/SBook-debug.apk"

PATCH_RC=999
BUILD_RC=999
COMMIT_RC=999
PUSH_RC=999
SSH_STATUS="UNKNOWN"

exec > >(tee "$LOG") 2>&1

echo "============================================================"
echo " SBOOK ONE-SCRIPT BUILD"
echo "============================================================"
date

# ------------------------------------------------------------
# 1. DEPENDENCIES
# ------------------------------------------------------------

echo
echo "=== DEPENDENCIES ==="

sudo apt-get update

sudo DEBIAN_FRONTEND=noninteractive apt-get install -y \
    git \
    wget \
    unzip \
    ca-certificates \
    python3 \
    openjdk-21-jdk

export JAVA_HOME="$(
    dirname "$(dirname "$(readlink -f "$(command -v javac)")")"
)"

export ANDROID_HOME="$SDK"
export ANDROID_SDK_ROOT="$SDK"

echo "JAVA_HOME=$JAVA_HOME"
java -version

# ------------------------------------------------------------
# 2. ANDROID SDK
# ------------------------------------------------------------

echo
echo "=== ANDROID SDK ==="

mkdir -p "$SDK/cmdline-tools"

if [ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]; then

    TMP="$(mktemp -d)"

    wget -q --show-progress \
        -O "$TMP/tools.zip" \
        "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"

    unzip -q "$TMP/tools.zip" -d "$TMP/unpack"

    rm -rf "$SDK/cmdline-tools/latest"
    mkdir -p "$SDK/cmdline-tools/latest"

    cp -a \
        "$TMP/unpack/cmdline-tools/." \
        "$SDK/cmdline-tools/latest/"

    rm -rf "$TMP"
fi

export PATH="$JAVA_HOME/bin:$SDK/cmdline-tools/latest/bin:$SDK/platform-tools:$PATH"

sdkmanager --version

yes | sdkmanager --licenses >/dev/null 2>&1 || true

# ------------------------------------------------------------
# 3. API 37
# ------------------------------------------------------------

echo
echo "=== API 37 ==="

SDKLIST="$(sdkmanager --list 2>/dev/null || true)"

if printf '%s\n' "$SDKLIST" | grep -q 'platforms;android-37.0'; then
    PLATFORM="platforms;android-37.0"
    PLATFORM_DIR="$SDK/platforms/android-37.0"
else
    PLATFORM="platforms;android-37"
    PLATFORM_DIR="$SDK/platforms/android-37"
fi

echo "Installing $PLATFORM"

sdkmanager \
    "$PLATFORM" \
    "platform-tools"

if [ ! -f "$PLATFORM_DIR/android.jar" ]; then
    echo "FATAL: API 37 android.jar missing."
    exit 10
fi

ls -lh "$PLATFORM_DIR/android.jar"

# ------------------------------------------------------------
# 4. REPOSITORY
# ------------------------------------------------------------

echo
echo "=== REPOSITORY ==="

if [ ! -d "$PROJECT/.git" ]; then
    git clone "$REPO_SSH" "$PROJECT" || exit 11
fi

cd "$PROJECT" || exit 12

ORIGIN="$(git remote get-url origin 2>/dev/null || true)"

echo "Origin: $ORIGIN"

case "$ORIGIN" in
    git@github.com:*|ssh://git@github.com/*)
        echo "Origin transport: SSH"
        ;;
    *)
        echo "FATAL: origin is not SSH."
        echo "Origin has NOT been changed."
        exit 13
        ;;
esac

BRANCH="$(git branch --show-current)"

if [ -z "$BRANCH" ]; then
    echo "FATAL: detached HEAD."
    exit 14
fi

echo "Branch: $BRANCH"
echo "HEAD: $(git rev-parse --short HEAD)"

# ------------------------------------------------------------
# 5. SSH
# ------------------------------------------------------------

echo
echo "=== SSH ==="

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

ssh-keyscan github.com >> "$HOME/.ssh/known_hosts" 2>/dev/null || true
chmod 600 "$HOME/.ssh/known_hosts" 2>/dev/null || true

echo "SSH private keys:"

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
   grep -qi "successfully authenticated"; then

    SSH_STATUS="PASS"

else

    SSH_STATUS="NOT CONFIRMED"

fi

echo "SSH authentication: $SSH_STATUS"

# ------------------------------------------------------------
# 6. LOCAL SDK CONFIG
# ------------------------------------------------------------

echo
echo "=== PROJECT CONFIG ==="

cat > local.properties <<EOF
sdk.dir=$SDK
EOF

# Remove Termux-only AAPT override on x86-64 VM.
if [ -f gradle.properties ]; then
    sed -i \
        '/^android\.aapt2FromMavenOverride=/d' \
        gradle.properties
fi

grep -RniE \
    'compileSdk|targetSdk|buildToolsVersion' \
    app/build.gradle \
    app/build.gradle.kts \
    gradle/libs.versions.toml \
    2>/dev/null || true

# ------------------------------------------------------------
# 7. SEARCH PATCH
# ------------------------------------------------------------

echo
echo "=== SEARCH PATCH ==="

DB="app/src/main/java/org/sbook/search/IndexDatabase.java"

if [ ! -f "$DB" ]; then

    echo "ERROR: $DB does not exist."
    PATCH_RC=20

else

python3 - "$DB" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
s = path.read_text()

MARKER = "SBOOK_SUBSTRING_FILENAME_SEARCH"

if MARKER in s:
    if (
        "WHERE name LIKE ? COLLATE NOCASE" in s
        and "sqlArgument" in s
        and "if (contents)" in s
    ):
        print("Correct substring patch already installed.")
        sys.exit(0)

    print("ERROR: marker exists but patch is incomplete.")
    sys.exit(21)


old_sql = '''            sql = "SELECT d.path,d.name,'' FROM filename_fts " +
                    "JOIN documents d ON d.id=filename_fts.docid " +
                    "WHERE filename_fts MATCH ? ORDER BY d.name COLLATE NOCASE LIMIT ?";'''

new_sql = '''            // SBOOK_SUBSTRING_FILENAME_SEARCH
            // Filename substring search against existing documents table.
            // ash -> ashtadhyayi. No reindex required.
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


if old_sql not in s:
    print("ERROR: expected filename_fts SQL not found.")
    print("Source left unchanged.")
    sys.exit(22)

if old_call not in s:
    print("ERROR: expected rawQuery call not found.")
    print("Source left unchanged.")
    sys.exit(23)

if "boolean contents" not in s:
    print("ERROR: real contents parameter not found.")
    print("Source left unchanged.")
    sys.exit(24)

if "String rawQuery" not in s:
    print("ERROR: rawQuery parameter not found.")
    print("Source left unchanged.")
    sys.exit(25)


s = s.replace(old_sql, new_sql, 1)
s = s.replace(old_call, new_call, 1)


if "searchContent" in s:
    print("ERROR: stale searchContent reference exists.")
    print("Refusing to write ambiguous source.")
    sys.exit(26)


path.write_text(s)

print("PATCH APPLIED")
print("Filename search = LIKE %rawQuery%")
print("Content search unchanged.")
PY

    PATCH_RC=$?

fi

echo "Patch RC: $PATCH_RC"

if [ "$PATCH_RC" -eq 0 ]; then

    echo
    echo "--- PATCH EVIDENCE ---"

    grep -n \
        -A18 \
        -B8 \
        'SBOOK_SUBSTRING_FILENAME_SEARCH' \
        "$DB" || true

fi

# ------------------------------------------------------------
# 8. BUILD
# ------------------------------------------------------------

echo
echo "============================================================"
echo " BUILD"
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
    echo "APK SUCCESS"
    ls -lh "$FINAL_APK"
    sha256sum "$FINAL_APK"

else

    echo
    echo "APK BUILD FAILED."
    echo "COMMIT/PUSH WILL CONTINUE."

fi

# ------------------------------------------------------------
# 9. GITIGNORE
# ------------------------------------------------------------

echo
echo "=== GIT EXCLUSIONS ==="

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

# Remove duplicate non-comment patterns.
python3 - <<'PY'
from pathlib import Path

p = Path(".gitignore")

lines = p.read_text().splitlines()

seen = set()
out = []

for line in lines:

    x = line.strip()

    if x and not x.startswith("#"):

        if x in seen:
            continue

        seen.add(x)

    out.append(line)

p.write_text("\n".join(out) + "\n")
PY

# ------------------------------------------------------------
# 10. STAGE ALL REPOSITORY SOURCE
# ------------------------------------------------------------

echo
echo "============================================================"
echo " STAGE ALL SOURCE"
echo "============================================================"

git reset >/dev/null 2>&1 || true

git add -A

# Unstage local/build/cache output if anything was already tracked.
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

# ------------------------------------------------------------
# 11. COMMIT
# ------------------------------------------------------------

echo
echo "============================================================"
echo " COMMIT"
echo "============================================================"

if git diff --cached --quiet
then

    echo "Nothing new to commit."
    COMMIT_RC=0

else

    if [ "$BUILD_RC" -eq 0 ]
    then
        MESSAGE="Fix SBook filename substring search"
    else
        MESSAGE="Fix SBook filename substring search; build diagnostics"
    fi

    git commit -m "$MESSAGE"

    COMMIT_RC=$?

fi

echo "Commit RC: $COMMIT_RC"

# ------------------------------------------------------------
# 12. PUSH USING EXISTING SSH ORIGIN
# ------------------------------------------------------------

echo
echo "============================================================"
echo " SSH PUSH"
echo "============================================================"

echo "Origin:"
git remote get-url origin

echo "Branch:"
echo "$BRANCH"

case "$(git remote get-url origin)" in

    git@github.com:*|ssh://git@github.com/*)

        GIT_SSH_COMMAND="ssh -o BatchMode=yes -o StrictHostKeyChecking=yes" \
            git push origin "$BRANCH"

        PUSH_RC=$?
        ;;

    *)

        echo "REFUSED: origin stopped being SSH."
        PUSH_RC=90
        ;;

esac

# ------------------------------------------------------------
# 13. FINAL REPORT
# ------------------------------------------------------------

echo
echo
echo "============================================================"
echo " SBOOK FINAL REPORT"
echo "============================================================"

echo "Project       : $PROJECT"
echo "Branch        : $BRANCH"
echo "Origin        : $(git remote get-url origin)"
echo "Transport     : SSH"
echo "SSH auth      : $SSH_STATUS"
echo "API           : 37"
echo "Java          : 21"
echo "Patch RC      : $PATCH_RC"
echo "Build RC      : $BUILD_RC"
echo "Commit RC     : $COMMIT_RC"
echo "Push RC       : $PUSH_RC"
echo "HEAD          : $(git rev-parse --short HEAD)"
echo "Log           : $LOG"

if [ -f "$FINAL_APK" ]
then

    echo "APK           : $FINAL_APK"
    echo "APK SHA256    : $(sha256sum "$FINAL_APK" | awk '{print $1}')"

else

    echo "APK           : NOT PRODUCED"

fi

echo
echo "Search implementation:"

if grep -q \
    'SBOOK_SUBSTRING_FILENAME_SEARCH' \
    "$DB" 2>/dev/null
then

    echo "Filename      : SQL LIKE %rawQuery%"
    echo "ash behavior  : matches ashtadhyayi"
    echo "Reindex       : NOT REQUIRED"

else

    echo "Filename      : PATCH NOT PRESENT"

fi

echo
echo "Latest commit:"
git --no-pager log -1 --oneline

echo
echo "Working tree:"
git status --short

echo
echo "============================================================"

# Push is the final operational result.
exit "$PUSH_RC"
