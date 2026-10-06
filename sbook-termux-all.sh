#!/data/data/com.termux/files/usr/bin/bash
set -Eeuo pipefail

REPO="https://github.com/viskie/sbook-search-android.git"
PROJECT="$HOME/sbook-search-android"
SDK="$HOME/android-sdk"

export ANDROID_HOME="$SDK"
export ANDROID_SDK_ROOT="$SDK"

echo
echo "======================================"
echo " 1/7 TERMUX DEPENDENCIES"
echo "======================================"

pkg update -y

pkg install -y \
    git \
    python \
    openjdk-21 \
    wget \
    unzip \
    aapt2

export JAVA_HOME="$PREFIX/lib/jvm/java-21-openjdk"
export PATH="$JAVA_HOME/bin:$PATH"

echo
echo "Java:"
java -version
javac -version

echo
echo "======================================"
echo " 2/7 ANDROID SDK COMMAND-LINE TOOLS"
echo "======================================"

mkdir -p "$SDK/cmdline-tools"

if [ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]; then

    cd "$HOME"

    rm -rf \
        commandlinetools.zip \
        cmdline-unpack

    wget -O commandlinetools.zip \
      "https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip"

    mkdir -p cmdline-unpack

    unzip -q commandlinetools.zip \
        -d cmdline-unpack

    mkdir -p "$SDK/cmdline-tools/latest"

    cp -a \
        cmdline-unpack/cmdline-tools/. \
        "$SDK/cmdline-tools/latest/"

    rm -rf \
        commandlinetools.zip \
        cmdline-unpack
fi

export PATH="$SDK/cmdline-tools/latest/bin:$SDK/platform-tools:$PATH"

echo
echo "sdkmanager:"
sdkmanager --version

echo
echo "======================================"
echo " 3/7 ANDROID SDK 35"
echo "======================================"

yes | sdkmanager --licenses >/dev/null 2>&1 || true

sdkmanager \
    "platforms;android-35" \
    "build-tools;35.0.0" \
    "platform-tools"

echo
echo "Installed SDK:"
echo "$SDK"

echo
echo "======================================"
echo " 4/7 GET SBOOK SOURCE"
echo "======================================"

if [ -d "$PROJECT/.git" ]; then

    cd "$PROJECT"

    echo "Existing repository found."

    if ! git diff --quiet ||
       ! git diff --cached --quiet; then

        echo
        echo "Local modifications exist."
        echo "Preserving them."
        echo "Skipping git pull."

    else

        git fetch origin
        git pull --ff-only origin main
    fi

else

    git clone "$REPO" "$PROJECT"
    cd "$PROJECT"
fi

echo
echo "Current commit:"
git log -1 --oneline

echo
echo "======================================"
echo " 5/7 CONFIGURE ANDROID BUILD"
echo "======================================"

cat > local.properties <<EOF
sdk.dir=$SDK
EOF

echo
echo "local.properties:"
cat local.properties

#
# Gradle normally downloads a desktop Linux aapt2.
# On ARM64 Termux use Termux's native executable.
#

AAPT2="$(command -v aapt2)"

if [ -z "$AAPT2" ]; then
    echo "ERROR: Termux aapt2 not found."
    exit 1
fi

touch gradle.properties

python - "$AAPT2" <<'PY'
from pathlib import Path
import sys

aapt2 = sys.argv[1]
p = Path("gradle.properties")

lines = p.read_text().splitlines()

lines = [
    line for line in lines
    if not line.startswith(
        "android.aapt2FromMavenOverride="
    )
]

lines.append(
    "android.aapt2FromMavenOverride=" + aapt2
)

p.write_text(
    "\n".join(lines) + "\n"
)
PY

echo
echo "AAPT2:"
echo "$AAPT2"

echo
echo "gradle.properties:"
cat gradle.properties

echo
echo "======================================"
echo " 6/7 PATCH SBOOK FILENAME SEARCH"
echo "======================================"

FILE="app/src/main/java/org/sbook/search/IndexDatabase.java"

if [ ! -f "$FILE" ]; then
    echo "ERROR:"
    echo "$FILE"
    echo "does not exist."
    exit 1
fi

#
# Keep a backup only once.
#

if [ ! -f "$FILE.before-substring-search" ]; then
    cp "$FILE" "$FILE.before-substring-search"
fi

python - <<'PY'
from pathlib import Path
import re

p = Path(
    "app/src/main/java/org/sbook/search/IndexDatabase.java"
)

s = p.read_text()

MARKER = "SBOOK_SUBSTRING_FILENAME_SEARCH"

if MARKER in s:
    print(
        "Filename substring-search patch "
        "already installed."
    )
    raise SystemExit(0)

#
# Find the existing filename FTS query.
#
# We ONLY replace filename searching.
#
# Content search, indexing, reindexing,
# notifications and progress are untouched.
#

pattern = re.compile(
    r'''
    (?P<indent>[ \t]*)
    sql\s*=\s*
    "SELECT\ d\.path,d\.name,''\ FROM\ filename_fts\ "\s*\+\s*
    "JOIN\ documents\ d\ ON\ d\.id=filename_fts\.docid\ "\s*\+\s*
    "WHERE\ filename_fts\ MATCH\ \?\ ORDER\ BY\ d\.name\ COLLATE\ NOCASE\ LIMIT\ \?";
    ''',
    re.VERBOSE
)

m = pattern.search(s)

if not m:

    print()
    print(
        "ERROR: expected filename_fts "
        "search query not found."
    )
    print()
    print(
        "NO SOURCE CODE WAS MODIFIED."
    )
    print()
    print("Relevant lines:")

    for number, line in enumerate(
        s.splitlines(), 1
    ):
        if (
            "filename_fts" in line
            or "MATCH ?" in line
            or "rawQuery" in line
        ):
            print(
                f"{number}: {line}"
            )

    raise SystemExit(2)

indent = m.group("indent")

replacement = (
    indent
    + '''/*
         * SBOOK_SUBSTRING_FILENAME_SEARCH
         *
         * Filename mode intentionally uses
         * substring matching.
         *
         * Examples:
         *
         * ash  -> ashtadhyayi
         * ashta -> ashtadhyayi
         * dhya -> ashtadhyayi
         *
         * Document-text search remains FTS.
         */
        sql = "SELECT path,name,'' FROM documents " +
              "WHERE name LIKE ? COLLATE NOCASE " +
              "ORDER BY name COLLATE NOCASE LIMIT ?";'''
)

s = (
    s[:m.start()]
    + replacement
    + s[m.end():]
)

#
# Existing implementation later executes:
#
# db.rawQuery(
#     sql,
#     new String[]{query, Integer.toString(limit)}
# )
#
# `query` is FTS formatted.
#
# Content mode still needs that.
#
# Filename mode instead needs:
#
#     %rawQuery%
#

raw_pattern = re.compile(
    r'''
    try\s*\(\s*
    Cursor\s+cursor\s*=\s*
    db\.rawQuery\(
        sql,\s*
        new\s+String\[\]\s*
        \{\s*
        query\s*,\s*
        Integer\.toString\(limit\)
        \s*\}
    \)
    \s*\)
    ''',
    re.VERBOSE
)

rm = raw_pattern.search(s)

if not rm:

    print()
    print(
        "ERROR: expected rawQuery call "
        "not found."
    )
    print(
        "Restoring original source."
    )

    backup = Path(
        str(p) +
        ".before-substring-search"
    )

    if backup.exists():
        p.write_text(
            backup.read_text()
        )

    raise SystemExit(3)

replacement = '''String sqlArgument;

        if (searchContent) {

            /*
             * Keep existing FTS expression for
             * Document Text mode.
             */
            sqlArgument = query;

        } else {

            /*
             * Filename mode:
             *
             * ash becomes %ash%
             */
            String filenameQuery =
                    rawQuery == null
                            ? ""
                            : rawQuery.trim();

            sqlArgument =
                    "%"
                    + filenameQuery
                    + "%";
        }

        try (Cursor cursor = db.rawQuery(
                sql,
                new String[]{
                        sqlArgument,
                        Integer.toString(limit)
                }))'''

s = (
    s[:rm.start()]
    + replacement
    + s[rm.end():]
)

p.write_text(s)

print()
print(
    "Filename substring search installed."
)
print(
    "Index/reindex/progress code untouched."
)
PY

echo
echo "---------- VERIFY PATCH ----------"

grep -n -A18 \
    'SBOOK_SUBSTRING_FILENAME_SEARCH' \
    "$FILE"

echo
echo
echo "---------- CHANGED FILE ----------"

git --no-pager diff -- "$FILE" || true

echo
echo "======================================"
echo " 7/7 BUILD APK"
echo "======================================"

chmod +x ./gradlew 2>/dev/null || true
chmod +x ./build.sh 2>/dev/null || true

echo
echo "Java:"
java -version

echo
echo "ANDROID_HOME:"
echo "$ANDROID_HOME"

echo
echo "AAPT2:"
echo "$AAPT2"

echo
echo "Starting Android compilation..."
echo

#
# This ONLY compiles the Android application.
# It does not rebuild the Sanskrit dataset.
#

if [ -x ./build.sh ]; then

    ./build.sh

elif [ -x ./gradlew ]; then

    ./gradlew assembleDebug

else

    echo "ERROR:"
    echo "Neither build.sh nor gradlew exists."
    exit 1
fi

echo
echo "======================================"
echo " BUILD FINISHED"
echo "======================================"

APK="$(find app/build/outputs/apk \
    -type f \
    -name '*.apk' \
    2>/dev/null |
    sort |
    tail -1)"

if [ -z "$APK" ]; then

    echo
    echo "ERROR:"
    echo "Build finished but APK was not found."
    exit 1
fi

echo
echo "APK:"
realpath "$APK"

echo
echo "File:"
ls -lh "$APK"

echo
echo "SHA256:"
sha256sum "$APK"

echo
echo "======================================"
echo " INSTALLATION"
echo "======================================"
echo
echo "Install this APK OVER the existing"
echo "SBook installation."
echo
echo "DO NOT:"
echo "  - clear SBook app data"
echo "  - uninstall the old app first"
echo "  - rebuild the 84K-file dataset"
echo
echo "Test Filename mode with:"
echo
echo "    ash"
echo "    ashta"
echo "    dhya"
echo
echo "These should reach filenames such as:"
echo
echo "    ashtadhyayi..."
echo
echo "======================================"
