#!/usr/bin/env bash
set -Eeuo pipefail

ROOT="$(pwd)"
JAVA="$ROOT/app/src/main/java/org/sbook/search"
LAYOUT="$ROOT/app/src/main/res/layout/activity_library.xml"
BACKUP="$ROOT/.filename-reindex-backup"

INDEX="$JAVA/IndexDatabase.java"
SERVICE="$JAVA/LibraryService.java"
ACTIVITY="$JAVA/LibraryActivity.java"

die() { echo "[ERROR] $*" >&2; exit 1; }
ok()  { echo "[OK] $*"; }

[[ -f "$ROOT/gradlew" ]] || die "Run from repository root."
[[ -f "$INDEX" ]] || die "IndexDatabase.java missing."
[[ -f "$SERVICE" ]] || die "LibraryService.java missing."
[[ -f "$ACTIVITY" ]] || die "LibraryActivity.java missing."
[[ -f "$LAYOUT" ]] || die "activity_library.xml missing."

mkdir -p "$BACKUP"

# ============================================================
# RESTORE
# ============================================================

if [[ "${1:-}" == "--restore" ]]; then
    for f in IndexDatabase.java LibraryService.java LibraryActivity.java activity_library.xml; do
        [[ -f "$BACKUP/$f" ]] || continue
        case "$f" in
            IndexDatabase.java) cp "$BACKUP/$f" "$INDEX" ;;
            LibraryService.java) cp "$BACKUP/$f" "$SERVICE" ;;
            LibraryActivity.java) cp "$BACKUP/$f" "$ACTIVITY" ;;
            activity_library.xml) cp "$BACKUP/$f" "$LAYOUT" ;;
        esac
    done

    ok "Original files restored."
    exit 0
fi

# ============================================================
# BACKUP ONCE
# ============================================================

[[ -f "$BACKUP/IndexDatabase.java" ]] ||
    cp "$INDEX" "$BACKUP/IndexDatabase.java"

[[ -f "$BACKUP/LibraryService.java" ]] ||
    cp "$SERVICE" "$BACKUP/LibraryService.java"

[[ -f "$BACKUP/LibraryActivity.java" ]] ||
    cp "$ACTIVITY" "$BACKUP/LibraryActivity.java"

[[ -f "$BACKUP/activity_library.xml" ]] ||
    cp "$LAYOUT" "$BACKUP/activity_library.xml"

ok "Backup ready."

# ============================================================
# PATCH IndexDatabase.java
# ============================================================

python3 - "$INDEX" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()

old = 'filename.put("name", name);'
new = 'filename.put("name", explodeFilenameForSearch(name));'

if new not in s:
    if old not in s:
        raise SystemExit(
            "Cannot locate filename FTS insertion; aborting safely."
        )
    s = s.replace(old, new, 1)

if "explodeFilenameForSearch(String name)" not in s:

    marker = "    private static String toMatchQuery(String raw) {"

    if marker not in s:
        raise SystemExit("Cannot locate toMatchQuery().")

    helper = r'''    private static String explodeFilenameForSearch(String name) {
        if (name == null) return "";

        return name
                .replaceAll("[^\\p{L}\\p{M}\\p{N}]+", " ")
                .trim()
                .replaceAll("\\s+", " ");
    }

'''

    s = s.replace(marker, helper + marker, 1)

p.write_text(s)
print("[OK] Filename FTS normalization patched.")
PY

# ============================================================
# PATCH LibraryService.java
# ============================================================

python3 - "$SERVICE" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()

# ------------------------------------------------------------
# Add ACTION_REINDEX
# ------------------------------------------------------------

old = '''    static final String ACTION_START = "org.sbook.search.START";'''

new = '''    static final String ACTION_START = "org.sbook.search.START";
    static final String ACTION_REINDEX = "org.sbook.search.REINDEX";'''

if "ACTION_REINDEX" not in s:
    if old not in s:
        raise SystemExit("ACTION_START not found.")
    s = s.replace(old, new, 1)

# ------------------------------------------------------------
# Teach service to accept REINDEX action
# ------------------------------------------------------------

old = '''        if (intent != null && ACTION_START.equals(intent.getAction()) && !running) {
            running = true;
            startForeground(NOTIFICATION_ID, notification("Preparing library", 0, true));
            worker.execute(this::installLibrary);
        }'''

new = '''        if (intent != null && !running) {
            if (ACTION_START.equals(intent.getAction())) {
                running = true;
                startForeground(
                        NOTIFICATION_ID,
                        notification("Preparing library", 0, true));
                worker.execute(this::installLibrary);

            } else if (ACTION_REINDEX.equals(intent.getAction())) {
                running = true;
                startForeground(
                        NOTIFICATION_ID,
                        notification("Reindexing existing library", 0, true));
                worker.execute(this::reindexExistingLibrary);
            }
        }'''

if "worker.execute(this::reindexExistingLibrary)" not in s:
    if old not in s:
        raise SystemExit("Current onStartCommand block not found.")
    s = s.replace(old, new, 1)

# ------------------------------------------------------------
# Add actual offline reindex implementation
# ------------------------------------------------------------

marker = '''    private void downloadParts(File partsDir) throws IOException {'''

if "private void reindexExistingLibrary()" not in s:

    if marker not in s:
        raise SystemExit("downloadParts marker not found.")

    code = r'''    private void reindexExistingLibrary() {
        IndexDatabase index = new IndexDatabase(this);

        try {
            File root = new File(getFilesDir(), "library");

            if (!root.isDirectory()) {
                throw new IOException(
                        "Downloaded library not found.");
            }

            publish(
                    "Reindexing",
                    "Scanning existing library…",
                    0,
                    0,
                    true,
                    false,
                    null,
                    true);

            SQLiteDatabase db =
                    index.getWritableDatabase();

            /*
             * Search DB only.
             *
             * Does NOT delete files/library.
             * Does NOT touch bookmark database.
             * Does NOT download anything.
             */
            index.reset(db);

            int[] count = {0};

            db.beginTransaction();

            try {
                reindexDirectory(
                        root,
                        root,
                        index,
                        db,
                        count);

                db.setTransactionSuccessful();

            } finally {
                db.endTransaction();
            }

            getSharedPreferences(PREFS, MODE_PRIVATE)
                    .edit()
                    .putBoolean(PREF_READY, true)
                    .putInt(PREF_COUNT, count[0])
                    .apply();

            publish(
                    "Ready",
                    formatCount(count[0]) +
                            " files reindexed",
                    100,
                    count[0],
                    false,
                    true,
                    null,
                    true);

            updateNotification(
                    "Reindex complete — " +
                            formatCount(count[0]) +
                            " files",
                    100,
                    false);

            stopForeground(STOP_FOREGROUND_REMOVE);
            stopSelf();

        } catch (Exception exception) {

            String message = exception.getMessage();

            if (message == null ||
                    message.isBlank()) {
                message =
                        exception
                                .getClass()
                                .getSimpleName();
            }

            publish(
                    "Reindex failed",
                    message,
                    0,
                    snapshot.files,
                    false,
                    false,
                    message,
                    true);

            updateNotification(
                    "Reindex failed: " + message,
                    0,
                    false);

            stopForeground(STOP_FOREGROUND_DETACH);
            stopSelf();

        } finally {
            running = false;
            index.close();
        }
    }


    private void reindexDirectory(
            File root,
            File directory,
            IndexDatabase index,
            SQLiteDatabase db,
            int[] count)
            throws IOException {

        File[] files = directory.listFiles();

        if (files == null)
            return;

        for (File file : files) {

            if (file.isDirectory()) {

                reindexDirectory(
                        root,
                        file,
                        index,
                        db,
                        count);

                continue;
            }

            if (!file.isFile())
                continue;

            String relative =
                    root.toPath()
                            .relativize(file.toPath())
                            .toString()
                            .replace(
                                    File.separatorChar,
                                    '/');

            String body = null;

            /*
             * Same content-indexing rule as original
             * extraction/indexing routine.
             */
            if (isTextFile(file.getName()) &&
                    file.length() <= MAX_INDEXED_FILE) {

                try (FileInputStream input =
                             new FileInputStream(file);

                     ByteArrayOutputStream text =
                             new ByteArrayOutputStream(
                                     (int) Math.min(
                                             file.length(),
                                             256 * 1024L))) {

                    byte[] buffer =
                            new byte[64 * 1024];

                    int read;

                    while ((read =
                            input.read(buffer)) != -1) {

                        text.write(
                                buffer,
                                0,
                                read);
                    }

                    body =
                            new String(
                                    text.toByteArray(),
                                    StandardCharsets.UTF_8);
                }
            }

            /*
             * logicalName stays ORIGINAL.
             *
             * IndexDatabase.insert() stores that original
             * name in documents, while only filename_fts
             * receives the exploded representation.
             */
            index.insert(
                    db,
                    relative,
                    logicalName(file.getName()),
                    body);

            count[0]++;

            if ((count[0] % 100) == 0) {

                publish(
                        "Reindexing",
                        formatCount(count[0]) +
                                " files • " +
                                file.getName(),
                        0,
                        count[0],
                        true,
                        false,
                        null,
                        false);
            }
        }
    }

'''

    s = s.replace(marker, code + marker, 1)

p.write_text(s)
print("[OK] Offline reindex action added.")
PY

# ============================================================
# PATCH activity_library.xml
# Add Reindex Library directly below New Category.
# ============================================================

python3 - "$LAYOUT" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()

if '@+id/reindexLibrary' not in s:

    marker = '''        android:text="+ New Category" />'''

    if marker not in s:
        raise SystemExit(
            "newCategory button not found in layout."
        )

    replacement = '''        android:text="+ New Category" />

    <Button
        android:id="@+id/reindexLibrary"

        android:layout_width="match_parent"
        android:layout_height="wrap_content"

        android:text="⟳ Reindex Library" />'''

    s = s.replace(marker, replacement, 1)

p.write_text(s)
print("[OK] Reindex Library button added.")
PY

# ============================================================
# PATCH LibraryActivity.java
# ============================================================

python3 - "$ACTIVITY" <<'PY'
from pathlib import Path
import sys

p = Path(sys.argv[1])
s = p.read_text()

# Add field
old = '''    private Button newCategory;'''

new = '''    private Button newCategory;
    private Button reindexLibrary;'''

if "private Button reindexLibrary;" not in s:
    if old not in s:
        raise SystemExit("newCategory field not found.")
    s = s.replace(old, new, 1)

# Find button
marker = '''        newCategory =
                findViewById(
                        R.id.newCategory
                );'''

replacement = '''        newCategory =
                findViewById(
                        R.id.newCategory
                );

        reindexLibrary =
                findViewById(
                        R.id.reindexLibrary
                );'''

if "R.id.reindexLibrary" not in s:
    if marker not in s:
        raise SystemExit(
            "newCategory findViewById block not found."
        )

    s = s.replace(marker, replacement, 1)

# Add click listener
marker = '''        newCategory
                .setOnClickListener(
                        v -> createCategory()
                );

        showCategories();'''

replacement = '''        newCategory
                .setOnClickListener(
                        v -> createCategory()
                );

        reindexLibrary
                .setOnClickListener(
                        v -> confirmReindex()
                );

        showCategories();'''

if "v -> confirmReindex()" not in s:
    if marker not in s:
        raise SystemExit(
            "newCategory listener block not found."
        )

    s = s.replace(marker, replacement, 1)

# Add methods before createCategory()
marker = '''    private void createCategory() {'''

if "private void confirmReindex()" not in s:

    code = '''    private void confirmReindex() {

        new AlertDialog.Builder(this)

                .setTitle(
                        "Reindex library?"
                )

                .setMessage(
                        "This rebuilds the search index from the " +
                        "already downloaded files.\\n\\n" +
                        "The library files and bookmarks will not " +
                        "be deleted or downloaded again."
                )

                .setPositiveButton(
                        "Reindex",

                        (dialog, which) ->
                                startReindex()
                )

                .setNegativeButton(
                        "Cancel",
                        null
                )

                .show();
    }


    private void startReindex() {

        Intent intent =
                new Intent(
                        this,
                        LibraryService.class
                );

        intent.setAction(
                LibraryService.ACTION_REINDEX
        );

        if (android.os.Build.VERSION.SDK_INT >=
                android.os.Build.VERSION_CODES.O) {

            startForegroundService(intent);

        } else {

            startService(intent);
        }

        Toast.makeText(
                this,
                "Reindex started",
                Toast.LENGTH_LONG
        ).show();
    }


'''

    if marker not in s:
        raise SystemExit(
            "createCategory marker not found."
        )

    s = s.replace(marker, code + marker, 1)

p.write_text(s)
print("[OK] LibraryActivity reindex control wired.")
PY

# ============================================================
# VERIFY
# ============================================================

echo
echo "========== VERIFY =========="

grep -n -C 2 \
    'explodeFilenameForSearch' \
    "$INDEX"

echo
grep -n -C 2 \
    'ACTION_REINDEX' \
    "$SERVICE"

echo
grep -n -C 2 \
    'reindexExistingLibrary' \
    "$SERVICE"

echo
grep -n -C 2 \
    'reindexLibrary' \
    "$ACTIVITY"

echo
grep -n -C 2 \
    'reindexLibrary' \
    "$LAYOUT"

echo
echo "========== DIFF =========="
git diff -- \
    "$INDEX" \
    "$SERVICE" \
    "$ACTIVITY" \
    "$LAYOUT"

# ============================================================
# BUILD
# ============================================================

echo
echo "========== BUILD =========="

chmod +x ./gradlew
./gradlew assembleDebug

APK="$ROOT/app/build/outputs/apk/debug/app-debug.apk"

[[ -f "$APK" ]] ||
    die "Build finished but APK not found."

echo
echo "======================================"
echo " SUCCESS"
echo "======================================"
echo
echo "APK:"
echo "  $APK"
echo
echo "Install it as an UPDATE."
echo "Do NOT uninstall the existing app."
echo
echo "After installation:"
echo
echo "  Home"
echo "    -> Library"
echo "    -> ⟳ Reindex Library"
echo "    -> Reindex"
echo
echo "The existing files/library corpus is reused."
echo "No dataset download occurs."
echo "Bookmarks remain untouched."
echo "Original filenames remain unchanged."
echo
echo "Restore source:"
echo "  ./patch-filename-reindex.sh --restore"